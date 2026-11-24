import Spec.Retro
open Spec.Retro
def cex : List Event := [⟨1, 2, .disburse 10⟩, ⟨2, 0, .disburse 10⟩, ⟨3, 1, .pay 20 .feeFirst⟩]
#eval ("rebuild", rebuildState cex)
#eval ("forkSync", forkSyncState cex, "agrees", forkSyncState cex == rebuildState cex, "stuck", (forkSync cex).stuck)
