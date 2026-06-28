// ABOUTME: Detects a project's tech stack from repo files and proposes a .dockyard.json draft.
// ABOUTME: Pure (filesystem-read only) so it can be unit-tested; the writer serializes the draft.

import Foundation

/// A proposed `.dockyard.json` configuration. Mirrors `ScriptConfig`'s writable fields.
struct DockyardConfigDraft: Equatable {
    var setup: String?
    var run: String?
    var teardown: String?
    var expectedPort: Int?

    enum FieldValidationError: Equatable {
        case invalidPort
    }

    struct FieldParseResult: Equatable {
        var draft: DockyardConfigDraft
        var validationError: FieldValidationError?
    }

    var isEmpty: Bool {
        setup == nil && run == nil && teardown == nil && expectedPort == nil
    }

    static func parseFields(
        setup: String,
        run: String,
        teardown: String,
        portText: String
    ) -> FieldParseResult {
        let trimmedSetup = nonEmpty(setup)
        let trimmedRun = nonEmpty(run)
        let trimmedTeardown = nonEmpty(teardown)
        let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPort.isEmpty else {
            return FieldParseResult(
                draft: DockyardConfigDraft(
                    setup: trimmedSetup,
                    run: trimmedRun,
                    teardown: trimmedTeardown,
                    expectedPort: nil
                ),
                validationError: nil
            )
        }

        guard let port = Int(trimmedPort), (1...65535).contains(port) else {
            return FieldParseResult(
                draft: DockyardConfigDraft(
                    setup: trimmedSetup,
                    run: trimmedRun,
                    teardown: trimmedTeardown,
                    expectedPort: nil
                ),
                validationError: .invalidPort
            )
        }

        return FieldParseResult(
            draft: DockyardConfigDraft(
                setup: trimmedSetup,
                run: trimmedRun,
                teardown: trimmedTeardown,
                expectedPort: port
            ),
            validationError: nil
        )
    }

    /// Serialize to pretty JSON, 2-space indent, in logical key order
    /// (setup, run, teardown, expectedPort). `JSONEncoder.sortedKeys` would
    /// alphabetize, which reads badly, so the order is built by hand.
    func jsonString() -> String {
        var parts: [String] = []
        if let setup { parts.append("  \"setup\": \(Self.encode(setup))") }
        if let run { parts.append("  \"run\": \(Self.encode(run))") }
        if let teardown { parts.append("  \"teardown\": \(Self.encode(teardown))") }
        if let expectedPort { parts.append("  \"expectedPort\": \(expectedPort)") }
        if parts.isEmpty { return "{}\n" }
        return "{\n" + parts.joined(separator: ",\n") + "\n}\n"
    }

    /// Encode a single string as a JSON string literal (handles escaping/quotes).
    private static func encode(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return str
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum StackDetector {
    /// Inspect `directory` and propose setup/run/teardown/expectedPort. A repo can
    /// match several stacks (e.g. Docker + Python); install steps are combined with `&&`.
    static func detect(at directory: String) -> DockyardConfigDraft {
        let fs = FileLookup(directory: directory)

        // Docker Compose contributes a setup prefix and a teardown, but never a `run`.
        let hasCompose = fs.exists("compose.yml") || fs.exists("docker-compose.yml")
            || fs.exists("compose.yaml") || fs.exists("docker-compose.yaml")

        var installSteps: [String] = []
        var run: String?
        var port: Int?

        // Node / TypeScript
        if fs.exists("package.json") {
            let pm = nodePackageManager(fs)
            installSteps.append("\(pm) install")
            let pkg = fs.json("package.json")
            if run == nil {
                let scripts = pkg?["scripts"] as? [String: Any]
                if scripts?["dev"] != nil {
                    run = "\(pm) run dev"
                } else if scripts?["start"] != nil {
                    run = "\(pm) run start"
                } else {
                    run = "\(pm) run dev"
                }
                port = nodePort(pkg)
            }
        }

        // Python — uv, then pip, then bare (mutually exclusive)
        if fs.exists("pyproject.toml"), fs.exists("uv.lock") {
            installSteps.append("uv sync")
            if run == nil {
                let manifest = (fs.read("pyproject.toml") ?? "").lowercased()
                (run, port) = pythonRun(fs, manifest: manifest, runner: .uv) ?? (run, port)
            }
        } else if fs.exists("requirements.txt") {
            installSteps.append("python -m venv .venv && .venv/bin/pip install -r requirements.txt")
            if run == nil {
                let manifest = (fs.read("requirements.txt") ?? "").lowercased()
                (run, port) = pythonRun(fs, manifest: manifest, runner: .pip) ?? (run, port)
            }
        } else if fs.exists("manage.py") {
            installSteps.append("uv venv && uv pip install django")
            if run == nil {
                run = ".venv/bin/python manage.py runserver"
                port = 8000
            }
        }

        // Rust
        if fs.exists("Cargo.toml") {
            installSteps.append("cargo fetch")
            if run == nil { run = "cargo run" }
        }

        // Go
        if fs.exists("go.mod") {
            installSteps.append("go mod download")
            if run == nil { run = "go run ." }
        }

        // Ruby
        if fs.exists("Gemfile") {
            installSteps.append("bundle install")
            if run == nil {
                let gemfile = (fs.read("Gemfile") ?? "").lowercased()
                if gemfile.contains("rails") || fs.exists("bin/rails") {
                    run = "bin/rails server"
                    if port == nil { port = 3000 }
                }
            }
        }

        // Elixir
        if fs.exists("mix.exs") {
            installSteps.append("mix deps.get")
            if run == nil {
                let mix = (fs.read("mix.exs") ?? "").lowercased()
                if mix.contains("phoenix") {
                    run = "mix phx.server"
                    if port == nil { port = 4000 }
                }
            }
        }

        // Makefile: prefer its setup/dev/run targets when present.
        let makeTargets = makefileTargets(fs)
        if makeTargets.contains("setup") { installSteps = ["make setup"] }
        if makeTargets.contains("dev") {
            run = "make dev"
        } else if makeTargets.contains("run") {
            run = "make run"
        }

        // Assemble setup: compose prefix first, then install steps.
        var setupSteps: [String] = []
        if hasCompose { setupSteps.append("docker compose up -d") }
        setupSteps.append(contentsOf: installSteps)
        let setup = setupSteps.isEmpty ? nil : setupSteps.joined(separator: " && ")
        let teardown = hasCompose ? "docker compose down" : nil

        return DockyardConfigDraft(setup: setup, run: run, teardown: teardown, expectedPort: port)
    }

    // MARK: - Node helpers

    private static func nodePackageManager(_ fs: FileLookup) -> String {
        if fs.exists("pnpm-lock.yaml") { return "pnpm" }
        if fs.exists("yarn.lock") { return "yarn" }
        if fs.exists("bun.lockb") { return "bun" }
        return "npm"
    }

    private static func nodePort(_ pkg: [String: Any]?) -> Int? {
        let names = nodeDependencyNames(pkg)
        if names.contains("astro") { return 4321 }
        if names.contains("next") { return 3000 }
        if names.contains("react-scripts") { return 3000 }
        if names.contains(where: { $0.hasPrefix("@remix-run/") }) { return 3000 }
        if names.contains("vite") { return 5173 }
        return nil
    }

    private static func nodeDependencyNames(_ pkg: [String: Any]?) -> Set<String> {
        var names = Set<String>()
        for key in ["dependencies", "devDependencies"] {
            if let deps = pkg?[key] as? [String: Any] { names.formUnion(deps.keys) }
        }
        return names
    }

    // MARK: - Python helpers

    private enum PythonRunner { case uv, pip }

    /// Returns the run command and expected port for a Python project, or nil if
    /// no recognizable entrypoint is found.
    private static func pythonRun(_ fs: FileLookup, manifest: String, runner: PythonRunner) -> (String?, Int?)? {
        let module = fs.exists("main.py") ? "main" : (fs.exists("app.py") ? "app" : "main")

        if fs.exists("manage.py") {
            switch runner {
            case .uv: return ("uv run python manage.py runserver", 8000)
            case .pip: return (".venv/bin/python manage.py runserver", 8000)
            }
        }
        if manifest.contains("fastapi") {
            switch runner {
            case .uv: return ("uv run uvicorn \(module):app --reload", 8000)
            case .pip: return (".venv/bin/uvicorn \(module):app --reload", 8000)
            }
        }
        if manifest.contains("flask") {
            switch runner {
            case .uv: return ("uv run flask run", 5000)
            case .pip: return (".venv/bin/flask run", 5000)
            }
        }
        if fs.exists("main.py") {
            switch runner {
            case .uv: return ("uv run python main.py", nil)
            case .pip: return (".venv/bin/python main.py", nil)
            }
        }
        return nil
    }

    // MARK: - Makefile helpers

    private static func makefileTargets(_ fs: FileLookup) -> Set<String> {
        guard let content = fs.read("Makefile") ?? fs.read("makefile") else { return [] }
        var targets = Set<String>()
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // Recipe lines start with a tab; comments with #; pattern rules / special
            // targets start with `.`. Real targets are `name:` at column 0.
            guard let first = line.first, first != "\t", first != " ", first != "#", first != "." else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !name.contains("=") { targets.insert(name) }
        }
        return targets
    }
}

// MARK: - Filesystem lookup

private struct FileLookup {
    let base: URL

    init(directory: String) {
        base = URL(fileURLWithPath: directory)
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: base.appendingPathComponent(relativePath).path)
    }

    func read(_ relativePath: String) -> String? {
        try? String(contentsOf: base.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func json(_ relativePath: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: base.appendingPathComponent(relativePath).path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - Writer

enum DockyardConfigWriter {
    /// Write a draft to `<directory>/.dockyard.json` as pretty JSON. Returns the path.
    @discardableResult
    static func write(_ draft: DockyardConfigDraft, to directory: String) throws -> String {
        let path = URL(fileURLWithPath: directory).appendingPathComponent(".dockyard.json").path
        try draft.jsonString().write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
