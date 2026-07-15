# Lifecycle race traces

These title-free traces are replayed by `./scripts/test.sh`. Each trace uses only numeric window identities and fixed diagnostic categories; no window title or other private content is recorded.

| Trace | Replay test | Safety invariant |
| --- | --- | --- |
| candidate-close | `targetDestructionBeforeModifierReleaseAdvancesWithoutFocusingAStaleWID` | selection advances and the removed identity is never focused |
| target-close-focus | `targetClosureDuringFocusFailsTheTransactionWithoutPromotingMRU` | session closes, recovery is requested and MRU is unchanged |
| target-close-deminimize | `targetClosureDuringDeminimizeFailsBeforeSkyLightFocus` | failed prerequisite cannot reach focus |
| WID-reuse-generation | `widReuseAndGenerationReplacementInvalidateTheCapturedSession` | replacement records inherit neither session state nor MRU |
| stale-focus-callback | `titleFreeTraceRejectsLateCompletionAndFinishesTheNewerTransaction` | an old completion cannot fail a newer transaction; the newer transaction terminates normally |
| internal-external-focus | `falseFocusSuccessRestoresOriginShowsErrorAndLeavesMRUUnchanged` | false success and reordered focus events cannot promote the wrong target |
| permission-revocation | `runtimeAccessibilityRevocationFailsClosedAndReleasesResources` | shortcuts, session, observers and inventory fail closed |
| permission-regrant | `permissionAndCapabilityCanRecoverWithoutRestarting` | readiness and inventory observation rebuild without restart |
| space-generation | `activeSpaceReplacementDropsOldGenerationAndStaleFieldsAreExplicit` | generations never mix and stale semantics fail closed |
| wake-reconstruction | `skyLightFailureRetriesOnlyForWakeOrUserRecheck` | reconstruction is event-triggered and begins from disabled state |
| adapter-restart | `permissionAndCapabilityCanRecoverWithoutRestarting` | stopped adapters rebuild one ready observation lifecycle |
| settings-recovery | `versionedSettingsRoundTripAndMalformedInputRecoversWithoutOverwritingEvidence` | malformed input preserves evidence and loads defaults |
| settings-migration | `versionOneSettingsMigrateToAnEmptyExceptionList`, `versionTwoSettingsMigrateSequentiallyToLaunchAndPresentationDefaults`, `malformedSettingsAreCopiedForDiagnosisBeforeDefaultsLoad` | historical fields migrate sequentially; truncated/future input fails closed with evidence preserved |
| duplicate-burst | `semanticBurstsRequestAtMostOneOutstandingAXEnrichment` | bursts coalesce to bounded enrichment work |
| lost-event-reconcile | `reconcileUsesWindowServerAsAuthorityWithoutResettingExistingMRU` | authoritative reconciliation repairs lost events without resetting valid MRU |
| AX-failure-timeout | `activeSpaceReplacementDropsOldGenerationAndStaleFieldsAreExplicit` | unavailable/stale fields fail qualification closed; production AX reads use bounded messaging timeouts off-main |
| SkyLight-load-query | `skyLightFailureRetriesOnlyForWakeOrUserRecheck`, `realReadOnlySkyLightCapabilityCheck` | capability/query failure disables shortcuts and requires an explicit recovery trigger |
| SkyLight-focus | `falseFocusSuccessRestoresOriginShowsErrorAndLeavesMRUUnchanged` | failed or false-success focus leaves MRU unchanged and requests recovery |
| shortcut-runtime-failure | `failedUnregistrationRemainsTrackedAndCanBeRetriedFailClosed` | unusable shortcuts stop consuming input and remain recoverable |
| diagnostic-privacy | `diagnosticTraceCannotCarryWindowContent` | a semantic title sentinel cannot enter the closed diagnostic event stream |

The complete replay also includes the real adapter smoke tests when their opt-in environment gates are enabled. A passing trace means the process did not crash; session-ending traces explicitly assert no active session, focus traces assert exact postconditions and MRU, shortcut traces assert pass-through/cleanup, and the privacy trace injects a sentinel title and proves it cannot enter the closed diagnostic stream.
