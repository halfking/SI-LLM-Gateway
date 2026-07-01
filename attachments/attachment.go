package attachments

import (
	"time"
)

// Attachment represents a stored attachment (image, file, etc.)
type Attachment struct {
	ID               string    `json:"id"`
	TenantID         string    `json:"tenant_id"`
	RequestID        string    `json:"request_id"`
	AttachmentType   string    `json:"attachment_type"`   // 'image', 'file', 'audio', 'video'
	MediaType        string    `json:"media_type"`        // MIME type: 'image/png', 'image/jpeg'
	FileSize         int64     `json:"file_size"`         // bytes
	FilePath         string    `json:"file_path"`         // filesystem path
	OriginalDataType string    `json:"original_data_type"` // 'base64', 'url'
	OriginalURL      *string   `json:"original_url,omitempty"`
	ContentHash      string    `json:"content_hash"`      // SHA256
	CreatedAt        time.Time `json:"created_at"`
	Metadata         []byte    `json:"metadata,omitempty"` // JSONB
}

// AttachmentType constants
const (
	TypeImage = "image"
	TypeFile  = "file"
	TypeAudio = "audio"
	TypeVideo = "video"
)

// OriginalDataType constants
const (
	DataTypeBase64 = "base64"
	DataTypeURL    = "url"
)

// AttachmentReference is embedded in request body to reference an attachment
type AttachmentReference struct {
	Type         string `json:"type"`          // "attachment_ref"
	AttachmentID string `json:"attachment_id"` // UUID
	MediaType    string `json:"media_type"`    // original MIME type
}
