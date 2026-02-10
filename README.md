# repo2doc

将任意仓库转成结构化分析报告，默认输出到 `Report/<ProjectName>/`。

## Skill 目录结构

- `SKILL.md`：技能入口与执行流程
- `references/spec.md`：严格产出规范（结构、证据、风险分级）
- `templates/`：报告模板骨架（可直接复制）
- `scripts/`：脚手架与校验脚本

## 默认报告结构（最小合同）

- `00-reading-guide.md`
- `A-01-getting-started.md`
- `B-01-deep-dive.md`
- `appendix-source-index.md`

## 自适应深挖章节（按项目特征选）

- `B-02-layered-highlights-and-hardparts.md`
- `B-10-temporal-behavior.md`
- `B-11-state-machine-analysis.md`
- `B-12-mechanism-implementation.md`
- `B-13-mechanism-flow.md`

## 脚本

- `scripts/scaffold-report.sh`
  - 最小生成：`scripts/scaffold-report.sh <ProjectName>`
  - 自适应章节：`scripts/scaffold-report.sh <ProjectName> --adaptive layered,state-machine,flow`
  - 生成支持章节：`scripts/scaffold-report.sh <ProjectName> --with-supporting`
- `scripts/validate-report.sh`
  - 基础校验：`scripts/validate-report.sh <ProjectName>`
  - 严格校验：`scripts/validate-report.sh <ProjectName> --strict --min-citations 5`
