// ABOUTME: System prompts injected into claude sessions based on settings.
// ABOUTME: Passed inline via --append-system-prompt.

import Foundation

enum SystemPrompts {
    static func restrictToWorktreePrompt(worktreePath: String) -> String {
        """
        CRITICAL FILESYSTEM CONSTRAINT: You MUST NOT create, edit, delete, or modify any files \
        outside of the following directory: \(worktreePath)
        This includes temporary files, configuration files, and any other filesystem writes. \
        All file operations MUST target paths within \(worktreePath). \
        If a task requires modifying files outside this path, explain what needs to change and \
        ask the user to do it manually or to enable unrestricted filesystem access in Settings.
        """
    }

    static let autoRenameBranchPrompt = """
    You are working inside Dockyard, a Mac app that runs coding agents in parallel worktrees. \
    Whenever the user presents a request that indicates a new task or a shift in intent (especially on the first request): \
    1) Summarize the user's intent from the latest prompt or series of prompts. \
    2) Generate two distinct names for the task: \
    - A concise, human-readable title in title case for the Dockyard tab, ideally 2-5 words. \
    - A git branch name using `<type>/<description>`, where type is an appropriate Conventional Commit type \
    such as `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `ci`, `perf`, or `build`. \
    Use concrete, specific language and avoid abstract nouns. \
    3) Rename the current branch using `git branch -m <type>/<description>`. \
    Do not preserve a generated prefix such as `dy/`; choose the type from the task's intent. \
    Use kebab-case and keep the descriptive part under 6 words. \
    4) Set the Dockyard tab title by writing only the concise human-readable title: \
    `mkdir -p .dockyard-state && printf '%s\\n' "your title" > .dockyard-state/description` \
    The tab title and branch name are separate values; do not use the kebab-case branch description as the tab title. \
    5) After renaming the branch and writing the title, continue with the task normally. \
    If the branch already has a perfectly accurate descriptive name for the current task, \
    skip the rename but still ensure the tab title is up to date. \
    Example: if the user asks to "refactor(localization): support English and Catalan only", \
    rename the branch to `refactor/english-and-catalan-only` and write "Remove Other Languages" to the description file.
    """
}
