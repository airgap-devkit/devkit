package tools

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// PackageItem describes an individual item in a bundle (pip wheel or VS Code extension).
type PackageItem struct {
	Name        string `json:"name"`
	ID          string `json:"id,omitempty"`          // e.g. ms-vscode.cpptools
	File        string `json:"file,omitempty"`        // .vsix filename if known
	Version     string `json:"version"`
	Category    string `json:"category,omitempty"`
	Description string `json:"description,omitempty"`
}

// Variant is a user-selectable install option for a tool that ships more than
// one prebuilt package (e.g. gRPC, one static-lib package per MSVC toolset).
// The label is surfaced in the UI/CLI; SetupArgs are passed to the setup script.
type Variant struct {
	ID        string   `json:"id"`
	Label     string   `json:"label"`
	Toolset   string   `json:"toolset,omitempty"`
	Archive   string   `json:"archive,omitempty"`
	SetupArgs []string `json:"setup_args,omitempty"`
	Default   bool     `json:"default,omitempty"`
}

type Tool struct {
	Hidden       bool          `json:"hidden"`
	ID           string        `json:"id"`
	Name         string        `json:"name"`
	Version      string        `json:"version"`
	Category     string        `json:"category"`
	Platform     string        `json:"platform"`
	Description  string        `json:"description"`
	Setup        string        `json:"setup"`
	ReceiptName  string        `json:"receipt_name"`
	CheckCmd        string   `json:"check_cmd"`
	CheckCmdWindows string   `json:"check_cmd_windows,omitempty"`
	CheckCmdLinux   string   `json:"check_cmd_linux,omitempty"`
	CheckBinary     string   `json:"check_binary,omitempty"`
	CheckArgs       []string `json:"check_args,omitempty"`
	Estimate     string        `json:"estimate"`
	UsesPrebuilt bool          `json:"uses_prebuilt"`
	SortOrder    int           `json:"sort_order"`
	SetupArgs    []string      `json:"setup_args"`
	VersionLabel string        `json:"version_label"`
	InstallLabel string        `json:"install_label,omitempty"`
	BundleType   string        `json:"bundle_type,omitempty"` // "pip" | "vscode"
	Packages     []PackageItem `json:"packages,omitempty"`
	VariantLabel string        `json:"variant_label,omitempty"`
	Variants     []Variant     `json:"variants,omitempty"`
	Source       string        `json:"source"`
	UploadedBy   string        `json:"uploaded_by,omitempty"`
	UploadedAt   string        `json:"uploaded_at,omitempty"`
	Homepage     string        `json:"homepage,omitempty"`
	License      string        `json:"license,omitempty"`
	GithubRepo   string        `json:"github_repo,omitempty"`
	AssetMatch   string        `json:"asset_match,omitempty"`
	TagPrefix    string        `json:"tag_prefix,omitempty"`
}

var scanPatterns = []struct {
	glob   string
	source string
}{
	{"tools/dev-tools/*/devkit.json", "builtin"},
	{"tools/dev-tools/*/*/devkit.json", "builtin"},
	{"tools/build-tools/*/devkit.json", "builtin"},
	{"tools/languages/*/devkit.json", "builtin"},
	{"tools/toolchains/*/devkit.json", "builtin"},
	{"tools/toolchains/*/*/devkit.json", "builtin"},
	{"tools/toolchains/*/*/*/devkit.json", "builtin"},
	{"tools/frameworks/*/devkit.json", "builtin"},
	{"packages/*/devkit.json", "builtin"},
	{"user-packages/*/devkit.json", "user"},
}

func Load(repoRoot string) ([]Tool, error) {
	var tools []Tool
	seen := map[string]bool{}

	for _, pat := range scanPatterns {
		matches, err := filepath.Glob(filepath.Join(repoRoot, filepath.FromSlash(pat.glob)))
		if err != nil {
			continue
		}
		sort.Strings(matches)
		for _, path := range matches {
			data, err := os.ReadFile(path)
			if err != nil {
				fmt.Fprintf(os.Stderr, "[devkit] warning: cannot read %s: %v\n", path, err)
				continue
			}
			var t Tool
			if err := json.Unmarshal(data, &t); err != nil {
				fmt.Fprintf(os.Stderr, "[devkit] warning: cannot parse %s: %v\n", path, err)
				continue
			}
			if t.ID == "" || seen[t.ID] || t.Hidden {
				continue
			}
			seen[t.ID] = true

			// Resolve setup path relative to the devkit.json directory
			if t.Setup != "" {
				abs := filepath.Join(filepath.Dir(path), t.Setup)
				rel, err := filepath.Rel(repoRoot, abs)
				if err == nil {
					t.Setup = filepath.ToSlash(rel)
				}
			}
			t.Source = pat.source
			if t.Platform == "" {
				t.Platform = "both"
			}
			if t.Category == "" {
				t.Category = "Developer Tools"
			}
			if t.Estimate == "" {
				t.Estimate = "~1min"
			}
			if t.ReceiptName == "" {
				t.ReceiptName = t.ID
			}
			if t.SetupArgs == nil {
				t.SetupArgs = []string{}
			}
			tools = append(tools, t)
		}
	}

	sort.Slice(tools, func(i, j int) bool {
		if tools[i].SortOrder != tools[j].SortOrder {
			return tools[i].SortOrder < tools[j].SortOrder
		}
		if tools[i].Category != tools[j].Category {
			return tools[i].Category < tools[j].Category
		}
		return strings.ToLower(tools[i].Name) < strings.ToLower(tools[j].Name)
	})
	return tools, nil
}

// ResolvedCheckCmd returns the most specific check command for the given OS:
// check_cmd_windows / check_cmd_linux take priority over check_cmd.
// Returns "" when no check command is configured for that platform.
func (t Tool) ResolvedCheckCmd(goos string) string {
	switch goos {
	case "windows":
		if t.CheckCmdWindows != "" {
			return t.CheckCmdWindows
		}
	case "linux", "darwin":
		if t.CheckCmdLinux != "" {
			return t.CheckCmdLinux
		}
	}
	return t.CheckCmd
}

// DefaultVariant returns the variant flagged default, or the first variant,
// or nil when the tool has no variants.
func (t Tool) DefaultVariant() *Variant {
	if len(t.Variants) == 0 {
		return nil
	}
	for i := range t.Variants {
		if t.Variants[i].Default {
			return &t.Variants[i]
		}
	}
	return &t.Variants[0]
}

// FindVariant returns the variant with the given id (case-insensitive), or nil.
func (t Tool) FindVariant(id string) *Variant {
	for i := range t.Variants {
		if strings.EqualFold(t.Variants[i].ID, id) {
			return &t.Variants[i]
		}
	}
	return nil
}

// InstallArgs returns the setup-script arguments for the given variant id.
// When the tool has variants, an unknown/empty id falls back to the default
// variant. A variant with explicit SetupArgs uses them; otherwise a
// "--toolset <toolset>" pair is synthesised. Tools without variants return
// their static SetupArgs unchanged.
func (t Tool) InstallArgs(variantID string) []string {
	if len(t.Variants) == 0 {
		return t.SetupArgs
	}
	v := t.FindVariant(variantID)
	if v == nil {
		v = t.DefaultVariant()
	}
	if v == nil {
		return t.SetupArgs
	}
	if len(v.SetupArgs) > 0 {
		return append(append([]string{}, t.SetupArgs...), v.SetupArgs...)
	}
	if v.Toolset != "" {
		return append(append([]string{}, t.SetupArgs...), "--toolset", v.Toolset)
	}
	return t.SetupArgs
}
