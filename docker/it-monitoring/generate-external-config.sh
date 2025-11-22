#!/bin/bash

CONFIG_FILE="config.yml"
OUTPUT_FILE="application-external.yml"

# 获取本机 IP 地址
function get_host_ip() {
  local host_ip=""
  
  # 优先使用 ip 命令
  if command -v ip >/dev/null 2>&1; then
    host_ip=$(ip addr | grep 'inet ' | grep -vE '127.0.0.1|docker' | awk '{print $2}' | cut -d/ -f1 | head -n1)
  # 降级使用 ifconfig
  elif command -v ifconfig >/dev/null 2>&1; then
    host_ip=$(ifconfig | awk '/^[a-zA-Z0-9]/ {iface=$1} /inet / && iface !~ /^(docker|br-|veth|lo)/ && $2!="127.0.0.1" {print $2}' | head -n1)
  fi
  
  # 验证 IP 格式
  if [[ "$host_ip" =~ ^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; then
    echo "$host_ip"
  else
    echo "localhost"
  fi
}

# 获取本机 IP
SERVER_IP=$(get_host_ip)
echo "检测到本机 IP: $SERVER_IP"

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

# 智能插入或更新 server-ip 配置
function inject_server_ip() {
    local content="$1"
    local result=""
    local in_tda=0
    local in_easy_config=0
    local tda_found=0
    local easy_config_found=0
    local tda_indent=""
    local easy_config_indent=""
    local server_ip_found=0
    local pending_lines=""
    
    while IFS= read -r line; do
        # 检测 tda: 节点（允许有前导空格）
        if [[ "$line" =~ ^([[:space:]]*)tda:[[:space:]]*$ ]]; then
            in_tda=1
            tda_found=1
            tda_indent="${BASH_REMATCH[1]}"
            result="$result$line"$'\n'
            pending_lines=""
            continue
        fi
        
        # 在 tda 节点内，检测 easy-config:
        if [[ "$in_tda" -eq 1 ]] && [[ "$line" =~ ^([[:space:]]+)easy-config:[[:space:]]*$ ]]; then
            in_easy_config=1
            easy_config_found=1
            easy_config_indent="${BASH_REMATCH[1]}"
            result="$result$line"$'\n'
            pending_lines=""
            continue
        fi
        
        # 在 easy-config 节点内
        if [[ "$in_easy_config" -eq 1 ]]; then
            # 检查是否已有 server-ip
            if [[ "$line" =~ ^[[:space:]]+server-ip:[[:space:]]*.* ]]; then
                # 找到 server-ip，输出之前的待处理行，然后替换 server-ip
                result="$result$pending_lines"
                result="$result${easy_config_indent}  server-ip: $SERVER_IP"$'\n'
                server_ip_found=1
                pending_lines=""
                continue
            fi
            
            # 检查是否是空行
            if [[ "$line" =~ ^[[:space:]]*$ ]]; then
                # 暂存空行，稍后决定是否输出
                pending_lines="$pending_lines$line"$'\n'
                continue
            fi
            
            # 检查是否遇到新的非空节点（离开 easy-config）
            if [[ "$line" =~ ^([[:space:]]*)[a-zA-Z_-]+:[[:space:]]*.*$ ]]; then
                local current_indent="${BASH_REMATCH[1]}"
                local current_indent_len=${#current_indent}
                local easy_config_indent_len=${#easy_config_indent}
                
                # 如果缩进小于等于 easy-config，说明离开了
                if [[ $current_indent_len -le $easy_config_indent_len ]]; then
                    # 在离开前插入 server-ip（如果还没有）
                    if [[ "$server_ip_found" -eq 0 ]]; then
                        result="$result${easy_config_indent}  server-ip: $SERVER_IP"$'\n'
                        server_ip_found=1
                    else
                        # 如果已经插入过 server-ip，输出待处理的行
                        result="$result$pending_lines"
                        pending_lines=""
                    fi
                    # 输出当前行
                    result="$result$line"$'\n'
                    in_easy_config=0
                    # 检查是否也离开了 tda
                    if [[ $current_indent_len -le ${#tda_indent} ]]; then
                        in_tda=0
                    fi
                    pending_lines=""
                    continue
                else
                    # 还在 easy-config 内的其他配置项，输出
                    result="$result$pending_lines"
                    result="$result$line"$'\n'
                    pending_lines=""
                    continue
                fi
            fi
            
            # 其他在 easy-config 内的行（如注释、值的延续等），输出
            result="$result$pending_lines"
            result="$result$line"$'\n'
            pending_lines=""
            continue
        fi
        
        # 在 tda 节点内但不在 easy-config 内
        if [[ "$in_tda" -eq 1 ]]; then
            # 检查是否是空行
            if [[ "$line" =~ ^[[:space:]]*$ ]]; then
                # 暂存空行
                pending_lines="$pending_lines$line"$'\n'
                continue
            fi
            
            # 检查是否遇到 tda 的同级节点（离开 tda）
            if [[ "$line" =~ ^([[:space:]]*)[a-zA-Z_-]+:[[:space:]]*.*$ ]]; then
                local current_indent="${BASH_REMATCH[1]}"
                local current_indent_len=${#current_indent}
                local tda_indent_len=${#tda_indent}
                
                # 如果缩进小于等于 tda，说明离开了 tda 节点
                if [[ $current_indent_len -le $tda_indent_len ]]; then
                    # 在离开 tda 前，如果没有 easy-config，则插入
                    if [[ "$easy_config_found" -eq 0 ]]; then
                        # 计算 easy-config 的缩进（tda 缩进 + 2 空格）
                        local new_easy_config_indent="${tda_indent}  "
                        result="$result${new_easy_config_indent}easy-config:"$'\n'
                        result="$result${new_easy_config_indent}  server-ip: $SERVER_IP"$'\n'
                        server_ip_found=1
                        easy_config_found=1
                    fi
                    # 输出待处理的行（可能包含空行）
                    result="$result$pending_lines"
                    pending_lines=""
                    in_tda=0
                fi
            fi
        fi
        
        # 不在特殊处理中的行，直接输出
        result="$result$line"$'\n'
    done <<< "$content"
    
    # 处理文件末尾的情况
    if [[ "$in_easy_config" -eq 1 ]] && [[ "$server_ip_found" -eq 0 ]]; then
        # easy-config 在文件末尾且为空，直接插入 server-ip
        result="$result${easy_config_indent}  server-ip: $SERVER_IP"$'\n'
        server_ip_found=1
    elif [[ "$in_tda" -eq 1 ]] && [[ "$easy_config_found" -eq 0 ]]; then
        # tda 在文件末尾但没有 easy-config，插入完整的 easy-config
        local new_easy_config_indent="${tda_indent}  "
        result="$result${new_easy_config_indent}easy-config:"$'\n'
        result="$result${new_easy_config_indent}  server-ip: $SERVER_IP"$'\n'
        server_ip_found=1
    fi
    
    # 如果整个文件都没有 tda，则在末尾添加完整结构
    if [[ "$tda_found" -eq 0 ]]; then
        result="${result%$'\n'}"$'\n'$'\n'"tda:"$'\n'"  easy-config:"$'\n'"    server-ip: $SERVER_IP"
    fi
    
    echo -n "$result"
}

# 根据结果写入输出文件
if [[ "$found_idmp" -eq 1 ]]; then
    # 删除末尾的空白行
    if [[ -n "$output_content" ]]; then
        # 注入 server-ip 配置
        final_content=$(inject_server_ip "${output_content%"$'\n"}")
        echo -n "$final_content" > "$OUTPUT_FILE"
    else
        # 空内容，直接创建 tda.easy-config.server-ip
        echo "tda:" > "$OUTPUT_FILE"
        echo "  easy-config:" >> "$OUTPUT_FILE"
        echo "    server-ip: $SERVER_IP" >> "$OUTPUT_FILE"
    fi
    
    echo "IDMP_CONFIG 配置已成功写入到 $OUTPUT_FILE"
    echo "已设置 tda.easy-config.server-ip = $SERVER_IP"
else
    echo "# IDMP_CONFIG 不存在" > "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "tda:" >> "$OUTPUT_FILE"
    echo "  easy-config:" >> "$OUTPUT_FILE"
    echo "    server-ip: $SERVER_IP" >> "$OUTPUT_FILE"
    echo "IDMP_CONFIG 不存在，已创建包含 server-ip 的 $OUTPUT_FILE"
    echo "已设置 tda.easy-config.server-ip = $SERVER_IP"
fi

echo "处理完成！"