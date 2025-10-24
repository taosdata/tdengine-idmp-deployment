#!/bin/bash

CONFIG_FILE="config.yml"
OUTPUT_FILE="application-external.yml"

# 检查配置文件是否存在，如果不存在则创建空文件并退出
if [ ! -f "$CONFIG_FILE" ]; then
    echo "# 配置文件 $CONFIG_FILE 不存在" > "$OUTPUT_FILE"
    echo "配置文件 $CONFIG_FILE 不存在，已创建空的 $OUTPUT_FILE"
    exit 0
fi

# 初始化变量
found_idmp=0
in_idmp_section=0
output_content=""
first_indent=""

# 读取配置文件并处理
while IFS= read -r line; do
    # 检查是否遇到 IDMP_CONFIG 节
    if [[ "$line" =~ ^IDMP_CONFIG: ]]; then
        found_idmp=1
        in_idmp_section=1
        continue
    fi

    # 检查是否遇到其他 CONFIG 节（表示 IDMP_CONFIG 节结束）
    if [[ "$in_idmp_section" -eq 1 ]] && [[ "$line" =~ ^[A-Z_]+_CONFIG: ]]; then
        break
    fi

    # 如果在 IDMP_CONFIG 节内，处理并保存内容
    if [[ "$in_idmp_section" -eq 1 ]]; then
        # 如果是第一个非空行，计算缩进量
        if [[ -z "$first_indent" ]] && [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
            # 提取行首的空白字符作为基准缩进
            if [[ "$line" =~ ^([[:space:]]+) ]]; then
                first_indent="${BASH_REMATCH[1]}"
            fi
        fi

        # 如果有基准缩进，去除基准缩进
        if [[ -n "$first_indent" ]]; then
            # 使用 sed 去除基准缩进
            trimmed_line=$(echo "$line" | sed "s/^$first_indent//")
            output_content="$output_content$trimmed_line"$'\n'
        else
            output_content="$output_content$line"$'\n'
        fi
    fi
done < "$CONFIG_FILE"

# 根据结果写入输出文件
if [[ "$found_idmp" -eq 1 ]]; then
    # 删除末尾的空白行
    if [[ -n "$output_content" ]]; then
        echo -n "${output_content%"$'\n"}" > "$OUTPUT_FILE"
    else
        echo -n "" > "$OUTPUT_FILE"
    fi
    echo "IDMP_CONFIG 配置已成功写入到 $OUTPUT_FILE"
else
    echo "# IDMP_CONFIG 不存在" > "$OUTPUT_FILE"
    echo "IDMP_CONFIG 不存在，已创建空的 $OUTPUT_FILE"
fi

echo "处理完成！"