package export

import (
	"encoding/json"
	"time"
)

type TeamConfig struct {
	ExportedAt string   `json:"exported_at"`
	Profile    string   `json:"profile"`
	ToolIDs    []string `json:"tool_ids"`
	Prefix     string   `json:"prefix"`
	DevkitName string   `json:"devkit_name"`
}

func Build(profile string, toolIDs []string, prefix, devkitName string) TeamConfig {
	return TeamConfig{
		ExportedAt: time.Now().UTC().Format(time.RFC3339),
		Profile:    profile,
		ToolIDs:    toolIDs,
		Prefix:     prefix,
		DevkitName: devkitName,
	}
}

func Marshal(tc TeamConfig) ([]byte, error) {
	return json.MarshalIndent(tc, "", "  ")
}

func Unmarshal(data []byte) (TeamConfig, error) {
	var tc TeamConfig
	err := json.Unmarshal(data, &tc)
	return tc, err
}
