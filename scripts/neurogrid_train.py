#!/usr/bin/env python3
"""
NeuroGrid W&B training launcher.

Launches a headless NeuroGrid simulation and logs per-generation metrics to
Weights & Biases using shared-evolve-utils/godot_wandb.py.

Usage:
  python scripts/neurogrid_train.py [--ticks N] [--project NAME] [--entity NAME]
  python scripts/neurogrid_train.py --sweep                     # W&B sweep agent mode

Environment:
  GODOT_PATH   Override path to Godot binary (default: /opt/homebrew/bin/godot)
  WANDB_API_KEY  Your W&B API key

The script expects shared-evolve-utils at ~/projects/shared-evolve-utils/.
"""

import argparse
import os
import sys
from pathlib import Path

# Resolve project root (one level up from scripts/)
PROJECT_DIR = Path(__file__).parent.parent.resolve()

# Add shared-evolve-utils to path
SHARED_UTILS = Path.home() / "projects" / "shared-evolve-utils"
if SHARED_UTILS.exists():
    sys.path.insert(0, str(SHARED_UTILS))

try:
    from godot_wandb import (
        godot_user_dir,
        launch_godot,
        poll_metrics,
        wait_for_metrics,
        write_config,
    )
except ImportError as e:
    print(f"ERROR: Cannot import shared-evolve-utils: {e}")
    print(f"Expected at: {SHARED_UTILS}")
    sys.exit(1)

try:
    import wandb
except ImportError:
    print("ERROR: wandb not installed. Run: pip install wandb")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

GODOT_PATH = os.environ.get("GODOT_PATH", "/opt/homebrew/bin/godot")
USER_DIR = godot_user_dir("neurogrid")
METRICS_PATH = USER_DIR / "metrics.json"
CONFIG_PATH = USER_DIR / "sweep_config.json"

# Default W&B project
DEFAULT_PROJECT = "neurogrid"


# ---------------------------------------------------------------------------
# Training config defaults
# ---------------------------------------------------------------------------

DEFAULT_CONFIG = {
    "ticks": 5000,
    # Sweepable GameConfig params (must match game_config.gd static vars)
    "BASE_METABOLISM": 0.15,
    "FOOD_REGEN_RATE": 0.08,
    "ADD_NODE_RATE": 0.03,
    "ADD_CONNECTION_RATE": 0.05,
    "INITIAL_POPULATION": 80,
    "REPRODUCTION_ENERGY_THRESHOLD": 35.0,
}


# ---------------------------------------------------------------------------
# Metric key mapping (metrics.json keys → W&B log keys)
# ---------------------------------------------------------------------------

METRIC_KEYS = [
    "best_fitness",
    "avg_fitness",
    "population",
    "species_count",
    "food_total",
    "avg_nodes",
    "avg_connections",
    "avg_receptors",
    "avg_skills",
]


# ---------------------------------------------------------------------------
# Training entry point
# ---------------------------------------------------------------------------


def train(config: dict | None = None) -> None:
    """Run one training session, logging to W&B."""
    with wandb.init(config=config) as run:
        cfg = dict(wandb.config)

        ticks: int = int(cfg.pop("ticks", DEFAULT_CONFIG["ticks"]))
        project_name: str = cfg.pop("project", DEFAULT_PROJECT)
        _ = cfg.pop("entity", None)  # consumed at wandb.init level

        # Build sweep CLI args from remaining config keys that match GameConfig
        sweep_args: list[str] = []
        sweepable = {
            "BASE_METABOLISM", "FOOD_REGEN_RATE", "ADD_NODE_RATE",
            "ADD_CONNECTION_RATE", "INITIAL_POPULATION",
            "REPRODUCTION_ENERGY_THRESHOLD",
        }
        for key, val in cfg.items():
            if key in sweepable:
                sweep_args += [f"--sweep-param", f"{key}={val}"]

        print(f"\n=== NeuroGrid Training — {run.name} ===")
        print(f"Ticks: {ticks}  |  Params: {cfg}")
        print(f"Metrics path: {METRICS_PATH}\n")

        # Ensure metrics file is removed so we detect fresh startup
        if METRICS_PATH.exists():
            METRICS_PATH.unlink()

        # Build Godot CLI: headless + ticks limit
        extra_args = ["--", "--ticks", str(ticks)] + sweep_args
        proc = launch_godot(
            godot_path=GODOT_PATH,
            project_path=str(PROJECT_DIR),
            visible=False,
            extra_args=extra_args,
        )

        # Wait for simulation to start writing metrics
        if not wait_for_metrics(METRICS_PATH, timeout=60):
            print("ERROR: Simulation did not start writing metrics within 60s")
            proc.terminate()
            return

        # Poll and log until training_complete
        poll_metrics(
            wandb_run=run,
            metrics_path=METRICS_PATH,
            max_gens=ticks // 500,  # generations ≈ ticks / GENERATION_INTERVAL
            poll_interval=2.0,
            metric_keys=METRIC_KEYS,
            step_key="generation",
        )

        proc.wait()
        print(f"Training complete — run: {run.url}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Launch NeuroGrid headless and log metrics to W&B."
    )
    parser.add_argument("--ticks", type=int, default=DEFAULT_CONFIG["ticks"],
                        help="Number of simulation ticks to run (default: 5000)")
    parser.add_argument("--project", default=DEFAULT_PROJECT,
                        help="W&B project name")
    parser.add_argument("--entity", default=None,
                        help="W&B entity (team/username)")
    parser.add_argument("--sweep", action="store_true",
                        help="Run as W&B sweep agent (config injected by sweep controller)")
    for key, val in DEFAULT_CONFIG.items():
        if key == "ticks":
            continue
        parser.add_argument(f"--{key.lower().replace('_', '-')}", type=float,
                            default=val, dest=key,
                            help=f"GameConfig.{key} (default: {val})")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if args.sweep:
        # W&B sweep agent: config comes from the sweep controller
        wandb.agent(
            sweep_id=os.environ.get("WANDB_SWEEP_ID", ""),
            function=train,
            project=args.project,
            entity=args.entity,
        )
        return

    # Single run with CLI config
    config = {
        "ticks": args.ticks,
        "project": args.project,
        "entity": args.entity,
    }
    for key in DEFAULT_CONFIG:
        if key != "ticks" and hasattr(args, key):
            config[key] = getattr(args, key)

    wandb.init(
        project=args.project,
        entity=args.entity,
        config=config,
    )
    train(config)


if __name__ == "__main__":
    main()
