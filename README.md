# repo2doc

将代码仓库整理为结构化项目文档。

## 快速开始

```bash
# 1. 发现模块
scripts/discover-modules.sh /path/to/repo --top 6 --format csv

# 2. 生成文档骨架
scripts/scaffold-report.sh MyProject --repo /path/to/repo --auto-modules 6

# 3. 填充内容后校验
scripts/validate-report.sh MyProject --strict --depth-profile audit --enforce
```

## 目录结构

- `SKILL.md` - 完整技能文档（含写作规范）
- `references/spec.md` - 技术规范
- `templates/` - 文档模板
- `scripts/` - 自动化脚本

## 脚本说明

| 脚本 | 用途 |
|------|------|
| `discover-modules.sh` | 按代码量发现核心模块 |
| `scaffold-report.sh` | 生成文档骨架 |
| `analyze-module.sh` | 分析单个模块结构 |
| `validate-report.sh` | 校验文档质量 |

## 自检

```bash
scripts/test-smoke.sh
```
