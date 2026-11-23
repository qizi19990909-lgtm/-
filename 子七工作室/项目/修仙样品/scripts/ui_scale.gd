extends Object
## 界面字号相对原来至少放大 30%，相关高度一并按同一比例加高。
const SCALE := 1.3

static func fs(sz: int) -> int:
	return int(ceili(float(sz) * SCALE))

static func px(v: int) -> int:
	return int(ceili(float(v) * SCALE))
