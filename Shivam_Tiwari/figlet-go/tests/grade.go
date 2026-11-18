package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type testCase struct {
	Args []string `json:"args"`
	Out  string   `json:"out"`
}

type result struct {
	Reward    float64 `json:"reward"`
	Build     float64 `json:"build"`
	NoPython  float64 `json:"no_python"`
	Behaviour float64 `json:"behaviour"`
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func round6(value float64) float64 {
	return math.Round(value*1_000_000) / 1_000_000
}

func loadCases(path string) ([]testCase, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var cases []testCase
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var item testCase
		if err := json.Unmarshal([]byte(line), &item); err != nil {
			return nil, fmt.Errorf("bad case: %w", err)
		}
		cases = append(cases, item)
	}
	return cases, scanner.Err()
}

func runBinary(binary string, args []string, timeout time.Duration) ([]byte, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, binary, args...)
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &bytes.Buffer{}
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return nil, false
	}
	if err != nil {
		return nil, false
	}
	return stdout.Bytes(), true
}

func hasPythonFiles(root string) (bool, error) {
	found := false
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		if strings.EqualFold(filepath.Ext(entry.Name()), ".py") {
			found = true
			return filepath.SkipAll
		}
		return nil
	})
	return found, err
}

func main() {
	testsDir := envOr("TESTS_DIR", "/tests")
	repoDir := envOr("REPO_DIR", "/workspace/repo")
	logsDir := envOr("LOGS_DIR", "/logs/verifier")
	binary := envOr("FIGLET_BIN", "/tmp/figlet")

	if err := os.MkdirAll(logsDir, 0o755); err != nil {
		fmt.Printf("cannot create log directory: %v\n", err)
	}

	build := 0.0
	_ = os.Remove(binary)
	buildCmd := exec.Command("go", "build", "-o", binary, ".")
	buildCmd.Dir = repoDir
	buildCmd.Env = append(os.Environ(), "CGO_ENABLED=0", "GOTOOLCHAIN=local")
	if output, err := buildCmd.CombinedOutput(); err == nil {
		build = 1.0
	} else {
		fmt.Printf("build failed: %v\n%s\n", err, output)
	}

	cases, caseErr := loadCases(filepath.Join(testsDir, "data", "hidden.jsonl"))
	if caseErr != nil {
		fmt.Printf("cannot load hidden cases: %v\n", caseErr)
		cases = nil
	}

	matches := 0
	if build == 1.0 {
		for _, item := range cases {
			stdout, ok := runBinary(binary, item.Args, 5*time.Second)
			if ok && bytes.Equal(stdout, []byte(item.Out)) {
				matches++
			}
		}
	}

	behaviour := 0.0
	if len(cases) > 0 {
		behaviour = float64(matches) / float64(len(cases))
	}

	noPython := 0.0
	if build == 1.0 && matches > 0 {
		pythonFound, err := hasPythonFiles(repoDir)
		if err == nil && !pythonFound {
			noPython = 1.0
		}
	}

	reward := (build + noPython + 4*behaviour) / 6.0
	payload := result{
		Reward:    round6(reward),
		Build:     build,
		NoPython:  noPython,
		Behaviour: round6(behaviour),
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		fmt.Printf("cannot encode reward: %v\n", err)
	} else if err := os.WriteFile(filepath.Join(logsDir, "reward.json"), encoded, 0o644); err != nil {
		fmt.Printf("cannot write reward.json: %v\n", err)
	}

	fmt.Printf("build=%v no_python=%v behaviour=%d/%d (%.6f) reward=%.6f\n",
		build, noPython, matches, len(cases), behaviour, payload.Reward)

	if behaviour == 1.0 {
		secretPath := filepath.Join(testsDir, "secret.b64")
		secret, err := os.ReadFile(secretPath)
		if err != nil {
			fmt.Printf("cannot read secret: %v\n", err)
			return
		}
		decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(secret)))
		if err != nil {
			fmt.Printf("cannot decode secret: %v\n", err)
			return
		}
		output, ok := runBinary(binary, []string{"-f", "slant", string(decoded)}, 5*time.Second)
		fmt.Println("*** SECRET UNLOCKED ***")
		if ok {
			os.Stdout.Write(output)
		} else {
			fmt.Println("(the program could not draw the secret)")
		}
	} else {
		fmt.Println("No secret for you. Yet.")
	}
}
