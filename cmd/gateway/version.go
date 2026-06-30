package main

import "time"

var (
	// Version is the semantic version
	Version = "v2.3.1-routing-fix"
	// BuildTime is when the binary was built
	BuildTime = ""
	// GitCommit is the git commit hash
	GitCommit = ""
	// BuildNumber increments with each build
	BuildNumber = ""
)

func init() {
	if BuildTime == "" {
		BuildTime = time.Now().Format("2006-01-02 15:04:05")
	}
}
