package admin

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/url"
	"strconv"
	"time"
)

// attachmentSigTTL is how long a signed attachment download URL remains
// valid. Browser <img>/<a> elements cannot attach an Authorization header,
// so the list API mints a short-lived, self-contained signature the browser
// can use directly (S3-presigned-URL style). 30 min is long enough for an
// admin to keep a detail drawer open while inspecting images, but short
// enough that a leaked link (browser history, nginx logs) quickly expires.
const attachmentSigTTL = 30 * time.Minute

// SignAttachmentURL returns the signed query string to append to an
// attachment download path: exp=<unix>&tenant=<id>&sig=<hex>.
//
// The signed message is "<id>|<exp>|<tenant>" keyed by secretKey. Tenant is
// bound into the signature so a link minted for tenant A cannot be replayed
// to download tenant B's attachment.
func SignAttachmentURL(id, tenantID, secretKey string) string {
	exp := time.Now().Add(attachmentSigTTL).Unix()
	sig := hmacSig(secretKey, fmt.Sprintf("%s|%d|%s", id, exp, tenantID))
	return fmt.Sprintf("exp=%d&tenant=%s&sig=%s", exp, url.QueryEscape(tenantID), sig)
}

// VerifyAttachmentURL validates a signed download request. id is the
// attachment id taken from the URL path; q is the parsed query string. On
// success it returns the tenant id embedded in the signature; the caller
// must still scope the DB lookup by this tenant so the signature alone can
// never widen access beyond what the issuer intended.
func VerifyAttachmentURL(id, secretKey string, q url.Values) (tenantID string, ok bool) {
	sig := q.Get("sig")
	if sig == "" {
		return "", false
	}
	expStr := q.Get("exp")
	expInt, err := strconv.ParseInt(expStr, 10, 64)
	if err != nil {
		return "", false
	}
	tenantID = q.Get("tenant")
	want := hmacSig(secretKey, fmt.Sprintf("%s|%d|%s", id, expInt, tenantID))
	if !hmac.Equal([]byte(want), []byte(sig)) {
		return "", false
	}
	if time.Now().Unix() >= expInt {
		return "", false // expired
	}
	return tenantID, true
}

func hmacSig(secretKey, msg string) string {
	mac := hmac.New(sha256.New, []byte(secretKey))
	mac.Write([]byte(msg))
	return hex.EncodeToString(mac.Sum(nil))
}
