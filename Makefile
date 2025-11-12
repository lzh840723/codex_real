.PHONY: plan patch spec test explain

# 默认目标
all: plan

plan:
	@./ai/ai.sh plan

patch:
	@./ai/ai.sh patch

spec:
	@./ai/ai.sh spec

test:
	@echo "Running tests..."
	@# 此处应添加实际的测试命令

explain:
	@./ai/ai.sh explain
