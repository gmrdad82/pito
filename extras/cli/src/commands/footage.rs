use anyhow::Result;

use crate::cli::FootageArgs;

pub fn run(_args: FootageArgs) -> Result<()> {
    println!(
        "`pito footage` will be wired up in Phase 4 — see docs/plans/beta/04-project-workspace/specs/project-workspace.md."
    );
    Ok(())
}
