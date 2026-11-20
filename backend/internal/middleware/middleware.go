// Package middleware 提供 Gin 中间件：CORS、JWT 鉴权、RBAC 等
package middleware

import (
	"strings"

	"meeting-platform/pkg/jwt"
	"meeting-platform/pkg/response"

	"github.com/gin-gonic/gin"
)

// corsConfig CORS 配置
type corsConfig struct {
	AllowOrigin  string
	AllowHeaders []string
	AllowMethods []string
}

// CORS CORS 中间件
// origins 支持两种写法：
//   - "*"                              → 允许所有来源
//   - "http://a,http://b,http://c"    → 逗号分隔的白名单（精确匹配 Origin 头）
func CORS(origins string) gin.HandlerFunc {
	allowAll := origins == "*"
	whitelist := make(map[string]struct{})
	if !allowAll {
		for _, o := range strings.Split(origins, ",") {
			o = strings.TrimSpace(o)
			if o != "" {
				whitelist[o] = struct{}{}
			}
		}
	}
	return func(c *gin.Context) {
		reqOrigin := c.GetHeader("Origin")
		if allowAll {
			c.Header("Access-Control-Allow-Origin", reqOrigin)
		} else if reqOrigin != "" {
			if _, ok := whitelist[reqOrigin]; ok {
				c.Header("Access-Control-Allow-Origin", reqOrigin)
			} else {
				c.AbortWithStatusJSON(403, gin.H{"code": 403, "message": "origin not allowed: " + reqOrigin})
				return
			}
		}
		c.Header("Access-Control-Allow-Credentials", "true")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

// ContextKey JWT Claims 注入到 Gin Context 的键
const ContextKey = "auth_claims"

// Auth JWT 鉴权中间件
func Auth(signer *jwtutil.Signer) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			response.Unauthorized(c, "missing authorization header")
			return
		}

		// 支持 "Bearer xxx" 或直接 "xxx"
		tokenStr := authHeader
		if strings.HasPrefix(authHeader, "Bearer ") {
			tokenStr = strings.TrimPrefix(authHeader, "Bearer ")
		}

		claims, err := signer.Parse(tokenStr)
		if err != nil {
			response.Unauthorized(c, "invalid or expired token")
			return
		}

		c.Set(ContextKey, claims)
		c.Next()
	}
}

// GetClaims 从 Context 中获取 JWT Claims；若不存在返回默认空值（不要直接用 nil）
func GetClaims(c *gin.Context) *jwtutil.Claims {
	v, ok := c.Get(ContextKey)
	if !ok {
		return &jwtutil.Claims{}
	}
	return v.(*jwtutil.Claims)
}

// TryGetClaims 若 Auth 中间件已注入则返回 (claims, true)，否则返回 (nil, false)
func TryGetClaims(c *gin.Context) (*jwtutil.Claims, bool) {
	v, ok := c.Get(ContextKey)
	if !ok {
		return nil, false
	}
	return v.(*jwtutil.Claims), true
}

// ParseToken 直接解析一个 token 字符串（给 WS query 鉴权使用）
func ParseToken(tokenStr string) (*jwtutil.Claims, error) {
	// 复用全局 signer 实例（main.go 初始化后会通过 SetSigner 注入）
	if globalSigner == nil {
		return nil, errSignerNotReady
	}
	claims, err := globalSigner.Parse(tokenStr)
	if err != nil {
		return nil, err
	}
	return claims, nil
}

// errSignerNotReady WS 提前调用时的错误
var errSignerNotReady = errSignerNotReadyType{}

type errSignerNotReadyType struct{}

func (errSignerNotReadyType) Error() string { return "signer not initialized" }

// globalSigner 全局 JWT signer 实例（由 main.go 注入）
var globalSigner *jwtutil.Signer

// SetSigner 供 main.go 注入 signer
func SetSigner(s *jwtutil.Signer) { globalSigner = s }

// RequireRole 要求用户角色在指定列表内
func RequireRole(roles ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		claims := GetClaims(c)
		if claims == nil {
			response.Unauthorized(c, "unauthorized")
			return
		}
		for _, r := range roles {
			if claims.Role == r {
				c.Next()
				return
			}
		}
		response.Forbidden(c, "forbidden: role not permitted")
	}
}
