package export

import "testing"

const profileCppDev = "cpp-dev"

func TestBuildMarshalUnmarshalRoundtrip(t *testing.T) {
	profiles := map[string]ProfileExport{
		profileCppDev: {ID: profileCppDev, Name: "C++ Dev", ToolIDs: []string{"cmake", "clang"}, Color: "blue"},
	}
	tc := Build("Team", "Org", "Kit", profileCppDev, []string{"cmake", "clang"}, "/opt/devkit", profiles)
	if tc.ExportedAt == "" {
		t.Error("Build did not stamp ExportedAt")
	}

	data, err := Marshal(tc)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	got, err := Unmarshal(data)
	if err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got.TeamName != "Team" || got.OrgName != "Org" || got.DevkitName != "Kit" ||
		got.Profile != profileCppDev || got.Prefix != "/opt/devkit" {
		t.Fatalf("scalar fields lost in roundtrip: %+v", got)
	}
	if len(got.ToolIDs) != 2 || got.ToolIDs[0] != "cmake" {
		t.Fatalf("tool ids lost: %+v", got.ToolIDs)
	}
	if p, ok := got.Profiles[profileCppDev]; !ok || p.Name != "C++ Dev" || len(p.ToolIDs) != 2 {
		t.Fatalf("profiles lost: %+v", got.Profiles)
	}
}

func TestUnmarshalInvalid(t *testing.T) {
	if _, err := Unmarshal([]byte("{not valid json")); err == nil {
		t.Fatal("Unmarshal accepted invalid JSON")
	}
}
