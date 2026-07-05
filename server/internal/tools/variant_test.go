package tools

import (
	"reflect"
	"testing"
)

const flagToolset = "--toolset"

func grpcTool() Tool {
	return Tool{
		ID:        "grpc",
		SetupArgs: []string{},
		Variants: []Variant{
			{ID: "v143", Toolset: "v143", SetupArgs: []string{flagToolset, "v143"}, Default: true},
			{ID: "v145", Toolset: "v145", SetupArgs: []string{flagToolset, "v145"}},
			{ID: "v142", Toolset: "v142", SetupArgs: []string{flagToolset, "v142"}},
		},
	}
}

func TestInstallArgs(t *testing.T) {
	tool := grpcTool()

	cases := map[string][]string{
		"v145":  {flagToolset, "v145"},
		"v142":  {flagToolset, "v142"},
		"V143":  {flagToolset, "v143"}, // case-insensitive match
		"":      {flagToolset, "v143"}, // empty -> default
		"bogus": {flagToolset, "v143"}, // unknown -> default
	}
	for in, want := range cases {
		if got := tool.InstallArgs(in); !reflect.DeepEqual(got, want) {
			t.Errorf("InstallArgs(%q) = %v, want %v", in, got, want)
		}
	}
}

func TestInstallArgsSynthesizesToolset(t *testing.T) {
	tool := Tool{
		Variants: []Variant{{ID: "v143", Toolset: "v143", Default: true}},
	}
	want := []string{flagToolset, "v143"}
	if got := tool.InstallArgs(""); !reflect.DeepEqual(got, want) {
		t.Errorf("synthesised args = %v, want %v", got, want)
	}
}

func TestInstallArgsNoVariants(t *testing.T) {
	tool := Tool{SetupArgs: []string{"--rebuild"}}
	if got := tool.InstallArgs("anything"); !reflect.DeepEqual(got, []string{"--rebuild"}) {
		t.Errorf("no-variant tool should return static SetupArgs, got %v", got)
	}
}

func TestDefaultVariant(t *testing.T) {
	if v := grpcTool().DefaultVariant(); v == nil || v.ID != "v143" {
		t.Fatalf("DefaultVariant = %+v, want v143", v)
	}
	// No explicit default -> first variant.
	tool := Tool{Variants: []Variant{{ID: "a"}, {ID: "b"}}}
	if v := tool.DefaultVariant(); v == nil || v.ID != "a" {
		t.Fatalf("DefaultVariant fallback = %+v, want a", v)
	}
	if (Tool{}).DefaultVariant() != nil {
		t.Fatal("DefaultVariant() should be nil with no variants")
	}
}
