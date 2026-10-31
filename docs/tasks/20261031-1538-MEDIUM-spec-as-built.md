# ТЗ plasma-thinkpad-fan как сделано + критик

Статус: в работе
Исполнитель: git-admin

## Что сделать
- Задание лида (31.10 ~15:4x CET) через git-admin (тикет ~/git/docs/tasks/20261031-1532-MEDIUM-reverse-spec-rollout.md): ТЗ plasma-thinkpad-fan «как сделано» + критика. Общий бриф /home/aisee/docs/reverse-spec/brief.md. Репо публичное: ТЗ (с цитатами и tl id) — в /home/aisee/.claude/tools/plasma-thinkpad-fan/spec.md (claude-config), не в репо; ветка spec-as-built не вливается.
- Автор: боец Terra (класс документация), бриф /home/aisee/.cache/worktrees/reverse-spec/plasma-thinkpad-fan/brief.md, пишет docs/spec.md.
- Критик: свежий боец Terra (класс ревью; Opus — только если Terra не справилась), вход — docs/spec.md, код и все источники, без вывода автора.
- Разбор: принято → tk на доработку, отклонено → причина строкой; разбор проверяет свежий агент.

## Приёмка
- Автор: /home/aisee/.cache/worktrees/reverse-spec/accept.sh 40 helpers/thinkpad-fan-hold helpers/thinkpad-fan-set helpers/thinkpad-fan-status package/contents/config package/contents/ui package/metadata.json polkit/com.github.aiseeq.thinkpadfan.policy install.sh make-plasmoid.sh в корне дерева — код 0; на дереве без docs/spec.md — код 1.
- ТЗ в /home/aisee/.claude/tools/plasma-thinkpad-fan/spec.md, закоммичено в claude-config; файл находок критика; у каждой находки решение (тикет или причина); итог git-admin.

## Журнал
- 2026-10-31 15:38 открыт — git-admin
- 2026-10-31 15:38 в работе — git-admin
- 2026-10-31 15:38 в работе — git-admin
- 2026-10-31 15:39 note — git-admin: автор: worker 1031-1539-spec-as-built-3 (terra, документация, --max 2h, --escalate none) запущен 15:39 CET; дерево ; бриф и приёмка — /home/aisee/.cache/worktrees/reverse-spec/plasma-thinkpad-fan/{brief.md,accept.cmd}; на дереве без spec приёмка — код 1
- 2026-10-31 15:39 note — git-admin: дерево автора: /home/aisee/.cache/worktrees/plasma-thinkpad-fan/spec-as-built (в прошлой строке путь пуст)
