---
name: Hardware report
about: Tell us whether FanShift works on your Mac (especially M1–M4)
title: "Hardware report: <Mac model>, <chip>, macOS <version>"
labels: hardware-report
---

**Mac**
- Model (Apple menu → About This Mac):
- Chip:
- macOS version:

**Did FanShift take over the fans?**
- [ ] Yes, the fans followed the curve
- [ ] No, the fans stayed under system control
- [ ] Something else (describe below)

**Output of `fanshiftctl status`**

Run this from the repository folder after building:

```
swift build && .build/debug/fanshiftctl status
```

```
(paste here)
```

**Helper log**

The last 20 lines of the helper's log (it records every takeover, release and unlock attempt):

```
tail -20 /var/log/com.kriswonka.fanshift.daemon.log
```

```
(paste here)
```

**Anything else**
