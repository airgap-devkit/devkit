package tools

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"testing"
)

func fakeExec(stdout string, exit int) func(string, ...string) *exec.Cmd {
	return func(name string, args ...string) *exec.Cmd {
		cs := append([]string{"-test.run=TestHelperProcess", "--", name}, args...)
		cmd := exec.Command(os.Args[0], cs...)
		cmd.Env = append(os.Environ(),
			"GO_WANT_HELPER_PROCESS=1",
			"HELPER_STDOUT="+stdout,
			"HELPER_EXIT="+strconv.Itoa(exit),
		)
		return cmd
	}
}

// TestHelperProcess is the child process spawned by fakeExec.
func TestHelperProcess(t *testing.T) {
	if os.Getenv("GO_WANT_HELPER_PROCESS") != "1" {
		return
	}
	fmt.Fprint(os.Stdout, os.Getenv("HELPER_STDOUT"))
	code, _ := strconv.Atoi(os.Getenv("HELPER_EXIT"))
	os.Exit(code)
}

func TestProbeSystemInstall(t *testing.T) {
	prev := execCommand
	defer func() { execCommand = prev }()

	execCommand = fakeExec("cmake version 3.29.1", 0)
	if got := probeSystemInstall("cmake --version", "linux"); got != "3.29.1" {
		t.Errorf("probe = %q, want 3.29.1", got)
	}

	// Empty check command short-circuits.
	if got := probeSystemInstall("", "linux"); got != "" {
		t.Errorf("empty checkCmd = %q, want empty", got)
	}

	// A non-zero exit is treated as "not present".
	execCommand = fakeExec("", 1)
	if got := probeSystemInstall("cmake --version", "linux"); got != "" {
		t.Errorf("failed probe = %q, want empty", got)
	}
}

func TestGetStatusSystemProbe(t *testing.T) {
	prev := execCommand
	defer func() { execCommand = prev }()
	execCommand = fakeExec("gcc 13.2.0", 0)

	tool := Tool{ID: "gcc", ReceiptName: "gcc", Version: "13.2.0", Platform: "both", CheckCmd: "gcc --version"}
	st := GetStatus(tool, t.TempDir(), "linux")
	if !st.Installed {
		t.Fatal("a successful system probe should mark the tool installed")
	}
	if st.Receipt.Date != "(system install)" {
		t.Fatalf("expected a system-install receipt: %+v", st.Receipt)
	}
}
