# finance_track_capabilities

Experimental pure policy for track-specific setup reports and provider-health
contracts. It validates that every required tool and health tool is prefixed by
the report's exact track, so CN cannot become ready because an HK or SEC tool is
installed.

Reports reuse `finance_track` currency/timezone interaction defaults and retain
a complete track context. Installed tools prove only that an Experimental typed
surface is present; connectivity, credentials, entitlement and freshness still
require a provider-specific probe. Unknown providers remain unknown.
