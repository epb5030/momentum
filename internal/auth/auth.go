package auth

import (
	"context"
	"crypto/rsa"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/lestrrat-go/jwx/v2/jwk"
)

// OIDCConfig holds OIDC provider configuration
type OIDCConfig struct {
	Issuer        string
	ClientID      string
	ClientSecret  string
	RedirectURL   string
	Scopes        []string
}

// JWTClaims represents the JWT claims
type JWTClaims struct {
	jwt.RegisteredClaims
	Email       string   `json:"email"`
	Workspaces  []WorkspaceClaim `json:"workspaces"`
	Scopes      []string `json:"scopes"`
}

type WorkspaceClaim struct {
	ID   string `json:"id"`
	Role string `json:"role"`
}

// Authenticator handles OIDC authentication and JWT validation
type Authenticator struct {
	config       OIDCConfig
	jwks         *jwk.Set
	jwksMu       sync.RWMutex
	jwksExpiry   time.Time
	httpClient   *http.Client
}

// NewAuthenticator creates a new authenticator
func NewAuthenticator(config OIDCConfig) *Authenticator {
	return &Authenticator{
		config:     config,
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

// fetchJWKS fetches the JWKS from the OIDC provider
func (a *Authenticator) fetchJWKS(ctx context.Context) error {
	a.jwksMu.Lock()
	defer a.jwksMu.Unlock()

	if time.Now().Before(a.jwksExpiry) && a.jwks != nil {
		return nil
	}

	jwksURL := strings.TrimRight(a.config.Issuer, "/") + "/.well-known/jwks.json"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, jwksURL, nil)
	if err != nil {
		return fmt.Errorf("create JWKS request: %w", err)
	}

	resp, err := a.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("fetch JWKS: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("JWKS request failed: %s", resp.Status)
	}

	jwks, err := jwk.ParseReader(resp.Body)
	if err != nil {
		return fmt.Errorf("parse JWKS: %w", err)
	}

	a.jwks = &jwks
	a.jwksExpiry = time.Now().Add(1 * time.Hour)
	return nil
}

// getSigningKey retrieves the signing key for a given key ID
func (a *Authenticator) getSigningKey(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	if err := a.fetchJWKS(ctx); err != nil {
		return nil, err
	}

	a.jwksMu.RLock()
	defer a.jwksMu.RUnlock()

	if a.jwks == nil {
		return nil, errors.New("JWKS not loaded")
	}

	// Fetch JWKS JSON directly and parse to find key by kid
	jwksURL := strings.TrimRight(a.config.Issuer, "/") + "/.well-known/jwks.json"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, jwksURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create JWKS request: %w", err)
	}

	resp, err := a.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch JWKS: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("JWKS request failed: %s", resp.Status)
	}

	var jwks struct {
		Keys []struct {
			Kid string          `json:"kid"`
			Key json.RawMessage `json:"key"`
		} `json:"keys"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return nil, fmt.Errorf("decode JWKS: %w", err)
	}

	for _, k := range jwks.Keys {
		if k.Kid == kid {
			var pubKey rsa.PublicKey
			if err := json.Unmarshal(k.Key, &pubKey); err != nil {
				return nil, fmt.Errorf("parse public key: %w", err)
			}
			return &pubKey, nil
		}
	}

	return nil, fmt.Errorf("key not found: %s", kid)
}

// ValidateToken validates a JWT token and returns the claims
func (a *Authenticator) ValidateToken(ctx context.Context, tokenString string) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}

		kid, ok := token.Header["kid"].(string)
		if !ok {
			return nil, errors.New("missing kid in token header")
		}

		return a.getSigningKey(ctx, kid)
	})

	if err != nil {
		return nil, fmt.Errorf("parse token: %w", err)
	}

	claims, ok := token.Claims.(*JWTClaims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}

	// Verify issuer
	if claims.Issuer != a.config.Issuer {
		return nil, fmt.Errorf("invalid issuer: %s", claims.Issuer)
	}

	// Verify audience
	if len(claims.Audience) > 0 && !contains(claims.Audience, a.config.ClientID) {
		return nil, errors.New("invalid audience")
	}

	return claims, nil
}

// contains checks if a slice contains a string
func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

// AuthMiddleware returns middleware that validates JWT tokens
func (a *Authenticator) AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()

		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "missing authorization header", http.StatusUnauthorized)
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			http.Error(w, "invalid authorization header format", http.StatusUnauthorized)
			return
		}

		claims, err := a.ValidateToken(ctx, parts[1])
		if err != nil {
			http.Error(w, fmt.Sprintf("invalid token: %v", err), http.StatusUnauthorized)
			return
		}

		// Add claims to context
		ctx = context.WithValue(ctx, "claims", claims)
		ctx = context.WithValue(ctx, "user_id", claims.Subject)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// RequireScope returns middleware that checks for a specific scope
func (a *Authenticator) RequireScope(scope string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := r.Context().Value("claims").(*JWTClaims)
		if !ok {
			http.Error(w, "missing claims", http.StatusUnauthorized)
			return
		}

		if !contains(claims.Scopes, scope) {
			http.Error(w, "insufficient scope", http.StatusForbidden)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// GetUserID extracts user ID from context
func GetUserID(ctx context.Context) (string, bool) {
	id, ok := ctx.Value("user_id").(string)
	return id, ok
}

// GetClaims extracts claims from context
func GetClaims(ctx context.Context) (*JWTClaims, bool) {
	claims, ok := ctx.Value("claims").(*JWTClaims)
	return claims, ok
}