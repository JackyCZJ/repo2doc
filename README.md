# repo2doc

将任意仓库转成结构化分析报告，默认输出到 `Report/<ProjectName>/`。

## Skill 目录结构

- `SKILL.md`：技能入口与执行流程
- `references/spec.md`：产出规范（证据、结构、风险分级）
- `templates/`：报告模板骨架（用于初始化内容）
- `scripts/`：脚手架与质量检查脚本

## 默认报告结构（最小合同）

- `00-reading-guide.md`
- `project-overview.md`
- `<module-name>.md`（一个或多个模块深挖文档）
- `appendix-source-index.md`

## 自适应专题（按项目特征选）

- `layered-highlights-and-hardparts.md`
- `temporal-behavior.md`
- `state-machine-analysis.md`
- `mechanism-implementation.md`
- `mechanism-flow.md`

## 脚本

- `scripts/scaffold-report.sh`
  - 最小生成：`scripts/scaffold-report.sh <ProjectName>`
  - 指定模块：`scripts/scaffold-report.sh <ProjectName> --modules api,worker,scheduler`
  - 自适应专题：`scripts/scaffold-report.sh <ProjectName> --adaptive layered,state-machine,flow`
  - 生成支撑章节：`scripts/scaffold-report.sh <ProjectName> --with-supporting`
- `scripts/validate-report.sh`
  - 默认为提示模式（不强制失败）：`scripts/validate-report.sh <ProjectName>`
  - 严格检查：`scripts/validate-report.sh <ProjectName> --strict --min-citations 5`
  - 强制失败（可选）：`scripts/validate-report.sh <ProjectName> --strict --enforce`
