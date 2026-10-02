#!/usr/bin/env python3
try:
    import pyatspi
except Exception as e:
    raise SystemExit(f"pyatspi unavailable: {e}")

def children(obj):
    try:
        count = int(obj.childCount)
    except Exception:
        return []
    out = []
    for i in range(count):
        try:
            out.append(obj.getChildAtIndex(i))
        except Exception:
            pass
    return out

desktop = pyatspi.Registry.getDesktop(0)
stack = [desktop]
seen = 0
found = 0

while stack and seen < 5000:
    obj = stack.pop()
    seen += 1
    try:
        role = obj.getRole()
    except Exception:
        role = None

    if role == pyatspi.ROLE_SCROLL_BAR:
        try:
            val = obj.queryValue()
            print(
                "SCROLLBAR",
                "name=", repr(getattr(obj, "name", "")),
                "current=", val.currentValue,
                "min=", val.minimumValue,
                "max=", val.maximumValue,
                "increment=", getattr(val, "minimumIncrement", None),
            )
            found += 1
        except Exception as e:
            print("SCROLLBAR without Value:", repr(e))

    stack.extend(children(obj))

print(f"Scanned {seen} accessibility nodes; found {found} value scrollbars.")
