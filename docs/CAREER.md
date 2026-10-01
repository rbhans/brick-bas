# Career mode

Career turns the sandbox into a game: you run a small controls contracting business and take contracts on the same three starter buildings, the same equipment and the same simulation the sandbox uses. Creative mode is unchanged: build anything, no goals.

Code: `scripts/career/` (`jobs.gd` is the catalog, `job_session.gd` runs a job, `career_state.gd` is the save, `service_catalog.gd` lists tests and repairs, `hvac_costs.gd` prices equipment). UI: `scripts/ui/job_panel.gd`, `service_panel.gd`, `controls_panel.gd`, and the board, briefing and results pages in `session_ui.gd`.

## The three kinds of work

Every job is graded on objectives. The plain objectives must all pass to finish the job (one star). Each ★ objective adds a star, up to three.

### Install

An occupied building with every piece of HVAC removed. Design the system in Equipment view: air handler (with a size and sections chosen on the workbench), VAVs, diffusers, ducts and thermostats. *Zone a room* still does the routine work. The clock is stopped while you design.

**Run commissioning day** time-lapses 06:30–18:00 on the job's weather and measures:

- Required: air in every occupied room (corridors, restrooms, storage and plant rooms don't count), and rooms holding setpoint (±2 °F) for the required share of 07:00–18:00.
- ★ The installed cost, priced from the model (`HvacCosts`), within the budget. The budget is the starter's own system × the job's factor.
- ★ The day's energy under the target, a little above what the reference design uses.

Edits are locked during the run. Afterwards you either hand the building over or keep improving and run it again. Overspend comes out of your fee.

### Service call

A running building with hidden faults that start during the morning, a work order, and a deadline. You travel there in time-lapse and then work live:

- Read the BAS. Every card has its readout and trend, the alarm list shows alarms (damper not following command, high space temperature, filter ΔP, SAT high, fan failure), and B tints rooms by temperature. Rooms that stay out of 68–76.5 °F for 15 minutes phone in a comfort call.
- Walk to the equipment (Explore, or *Walk over* for two minutes of clock) and press E to service it.
- **Tests** cost a few minutes and report what a tech would find: a stroke test on a damper or valve, a belt inspection, filter ΔP, a reference thermometer against the thermostat.
- **Repairs** cost time and parts. The right part fixes the fault in the simulation. A part that fixes nothing comes out of your fee and loses the "no unnecessary parts" star.

Close out when you're done. The rest of the day then plays out to the deadline, so the comfort star reflects whether your fixes actually held.

| Fault | What it does | Where it shows | The fix |
| --- | --- | --- | --- |
| Stuck VAV damper | blade frozen | damper command ≠ feedback, starved room, damper alarm | damper actuator |
| Stuck reheat valve | shut (cold room) or open (hot room, gas) | reheat command ≠ output, discharge temperature | reheat valve actuator |
| Miscalibrated sensor | thermostat reads off | room "on setpoint" yet complaining; reference thermometer disagrees | recalibrate (or replace) |
| Tampered setpoints | someone set 64 °F | setpoints on the thermostat or card | reset, or adjust it back |
| Broken fan belt | fan stops while commanded | fan alarm, zero airflow | fan belt |
| Loaded filters | 500 Pa at design flow | filter ΔP alarm (normalized to airflow), less air at peak | filters |
| Stuck cooling valve | chilled water frozen | SAT high alarm, warm building | cooling valve actuator |
| Stuck OA damper | wide open | 100 % outdoor air, big cooling or heating load | OA damper actuator |

### Tune-up

A comfortable building with wasteful programming: a 04:00–22:00 schedule, no optimal start, fixed 55 °F supply air, fixed 1.6 in. w.c. static, economizer and DCV off, 60 % VAV minimums, and tight setpoints. Open **BAS programming** and fix what's wasting energy. Each setting is a real sequence (see [SIMULATION.md](SIMULATION.md#bas-programming)). The "default sequences" shortcut is hidden during a tune-up.

**Run verification day** measures midnight to midnight against the as-found bill:

- Required: cut the bill by the job's share, keep rooms 68–76.5 °F, and keep CO₂ under 1,400 ppm for 90 % of the occupied day. People keep their 07:00–18:00 hours whatever the schedule says, so switching the building off fails.
- ★ Deeper cuts.

## Progress

`user://career.json` stores the company, bank balance and best stars per job. A first completion pays the fee. A replay pays only the share of the fee its extra stars add. Ranks come from total stars (Apprentice, Technician at 4, Lead technician at 10, Controls engineer at 17, Master of the mechanical room at 24), and the job tiers unlock at 0, 4 and 10 stars.

**On call** opens after the first star: endless random service calls. They are deterministic per call number, harder with rank, and use the weather each fault needs to show. They pay but don't count toward rank.

Jobs aren't saved part-way. Leaving a job keeps the building as a sandbox.

## The jobs

| Tier | Job | Kind | Building · weather | Notes |
| --- | --- | --- | --- | --- |
| 1 | It's an oven in here | Service | Workshop · hot afternoon | stuck damper; the tutorial |
| 1 | Fit out the corner workshop | Install | Workshop · normal | first design |
| 1 | Cold start | Service | Workshop · cold morning | stuck-shut reheat + tampered thermostat |
| 2 | The office that never sleeps | Tune-up | Office · economizer day | as found ≈ $13/day; good programming ≈ $2.8 |
| 2 | Meeting in a meat locker | Service | Office · normal | sensor reads 6.5 °F warm + loaded filters |
| 2 | Neighborhood office build-out | Install | Office · hot afternoon | air handler sizing matters |
| 3 | Heat wave emergency | Service | School · hot afternoon | cooling valve, OA damper, classroom damper |
| 3 | School energy audit | Tune-up | School · cold morning | as found ≈ $64/day; good ≈ $27 |
| 3 | Maple Street Elementary | Install | School · normal | 15 rooms, two units |
| 3 | The final inspection | Service | School · cold morning | four faults, one on a unit that fails mid-morning |

## Adding or tuning a job

Add an entry to `CareerJobs.JOBS`. Faults name equipment the way the starters do: `"ahu": "AHU-1"`, `"vav": "<room the VAV serves>"`, `"room": "<room>"` (sensor bias and setpoints act on the room's thermostat). `onset_h` sets when a fault starts.

Targets come from the simulation, never guesses. `tests/career_mode.gd -- --calibrate` plays every job as a competent player would (installs build and, if needed, upsize the reference design; service calls test, then fit the right parts; tune-ups apply the default sequences) and prints install energy and tune-up baselines. Without `--calibrate` it asserts that every job can be won with three stars, that the targets aren't loose, and that switching a building off doesn't pass. `tools/career_calibrate.gd` prints full-day energy and comfort for each starter, weather and programming, and `tools/career_probe.gd` shows where a starter's air goes at a given hour.
