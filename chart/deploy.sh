#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Apache Airflow Helm Chart 快速部署脚本
# 使用方法: ./deploy.sh [选项]

set -e

# 默认配置
RELEASE_NAME="airflow"
NAMESPACE="airflow"
CHART_PATH="."
LOAD_EXAMPLES="false"
EXECUTOR="LocalExecutor"
AIRFLOW_TAG="3.1.3"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印帮助信息
print_help() {
    cat << EOF
Apache Airflow Helm Chart 部署脚本

用法: $0 [选项]

选项:
  -n, --namespace NAME      指定命名空间 (默认: airflow)
  -r, --release NAME        指定 Helm release 名称 (默认: airflow)
  -e, --executor TYPE       指定执行器类型 (默认: LocalExecutor)
                           可选: LocalExecutor, CeleryExecutor, KubernetesExecutor
  -t, --tag TAG            指定 Airflow 镜像标签 (默认: 3.1.3)
  -x, --examples            启用示例 DAGs
  -f, --values FILE         使用自定义 values 文件
  -u, --upgrade             升级现有部署
  -d, --delete              删除部署
  -s, --status              查看部署状态
  -p, --port-forward        启动端口转发到 Web UI
  -h, --help                显示此帮助信息

示例:
  # 基本部署
  $0

  # 使用自定义命名空间和启用示例 DAGs
  $0 -n my-airflow -x

  # 使用 Celery Executor
  $0 -e CeleryExecutor

  # 使用自定义 values 文件
  $0 -f my-values.yaml

  # 升级部署
  $0 -u -t 3.1.4

  # 查看状态
  $0 -s

  # 启动端口转发
  $0 -p

  # 删除部署
  $0 -d
EOF
}

# 检查前置条件
check_prerequisites() {
    echo -e "${YELLOW}检查前置条件...${NC}"
    
    # 检查 kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}错误: 未找到 kubectl，请先安装 kubectl${NC}"
        exit 1
    fi
    
    # 检查 helm
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}错误: 未找到 helm，请先安装 Helm 3.0+${NC}"
        exit 1
    fi
    
    # 检查 Kubernetes 连接
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}错误: 无法连接到 Kubernetes 集群${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}前置条件检查通过${NC}"
}

# 创建命名空间
create_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "${YELLOW}创建命名空间: $NAMESPACE${NC}"
        kubectl create namespace "$NAMESPACE"
    else
        echo -e "${GREEN}命名空间 $NAMESPACE 已存在${NC}"
    fi
}

# 部署 Airflow
deploy_airflow() {
    echo -e "${YELLOW}开始部署 Airflow...${NC}"
    
    local helm_args=(
        "install"
        "$RELEASE_NAME"
        "$CHART_PATH"
        "--namespace" "$NAMESPACE"
    )
    
    # 添加执行器配置
    helm_args+=("--set" "executor=$EXECUTOR")
    
    # 添加镜像标签
    helm_args+=("--set" "images.airflow.tag=$AIRFLOW_TAG")
    
    # 添加示例 DAGs
    if [ "$LOAD_EXAMPLES" = "true" ]; then
        helm_args+=(
            "--set-string" "env[0].name=AIRFLOW__CORE__LOAD_EXAMPLES"
            "--set-string" "env[0].value=True"
        )
    fi
    
    # 添加自定义 values 文件
    if [ -n "$VALUES_FILE" ]; then
        helm_args+=("-f" "$VALUES_FILE")
    fi
    
    helm "${helm_args[@]}"
    
    echo -e "${GREEN}部署完成！${NC}"
}

# 升级部署
upgrade_airflow() {
    echo -e "${YELLOW}升级 Airflow 部署...${NC}"
    
    local helm_args=(
        "upgrade"
        "$RELEASE_NAME"
        "$CHART_PATH"
        "--namespace" "$NAMESPACE"
    )
    
    # 添加执行器配置
    helm_args+=("--set" "executor=$EXECUTOR")
    
    # 添加镜像标签
    helm_args+=("--set" "images.airflow.tag=$AIRFLOW_TAG")
    
    # 添加示例 DAGs
    if [ "$LOAD_EXAMPLES" = "true" ]; then
        helm_args+=(
            "--set-string" "env[0].name=AIRFLOW__CORE__LOAD_EXAMPLES"
            "--set-string" "env[0].value=True"
        )
    fi
    
    # 添加自定义 values 文件
    if [ -n "$VALUES_FILE" ]; then
        helm_args+=("-f" "$VALUES_FILE")
    fi
    
    helm "${helm_args[@]}"
    
    echo -e "${GREEN}升级完成！${NC}"
}

# 删除部署
delete_airflow() {
    echo -e "${YELLOW}删除 Airflow 部署...${NC}"
    read -p "确定要删除 $RELEASE_NAME 吗? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE"
        echo -e "${GREEN}删除完成！${NC}"
    else
        echo -e "${YELLOW}已取消删除${NC}"
    fi
}

# 查看状态
show_status() {
    echo -e "${YELLOW}部署状态:${NC}"
    echo ""
    echo "=== Helm Release ==="
    helm list --namespace "$NAMESPACE" | grep "$RELEASE_NAME" || echo "未找到 release"
    echo ""
    echo "=== Pods ==="
    kubectl get pods --namespace "$NAMESPACE" -l release="$RELEASE_NAME" 2>/dev/null || \
    kubectl get pods --namespace "$NAMESPACE"
    echo ""
    echo "=== Services ==="
    kubectl get svc --namespace "$NAMESPACE" | grep "$RELEASE_NAME" || \
    kubectl get svc --namespace "$NAMESPACE"
}

# 端口转发
port_forward() {
    echo -e "${YELLOW}启动端口转发到 Airflow Web UI...${NC}"
    echo "访问地址: http://localhost:8080"
    echo "按 Ctrl+C 停止端口转发"
    kubectl port-forward "svc/${RELEASE_NAME}-api-server" 8080:8080 --namespace "$NAMESPACE"
}

# 获取管理员密码
get_admin_password() {
    echo -e "${YELLOW}获取管理员密码...${NC}"
    local secret_name="${RELEASE_NAME}-webserver-secret"
    if kubectl get secret "$secret_name" --namespace "$NAMESPACE" &> /dev/null; then
        kubectl get secret "$secret_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath="{.data.admin-password}" | base64 -d
        echo ""
    else
        echo -e "${RED}未找到 secret: $secret_name${NC}"
    fi
}

# 解析命令行参数
UPGRADE=false
DELETE=false
STATUS=false
PORT_FORWARD=false
VALUES_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -e|--executor)
            EXECUTOR="$2"
            shift 2
            ;;
        -t|--tag)
            AIRFLOW_TAG="$2"
            shift 2
            ;;
        -x|--examples)
            LOAD_EXAMPLES="true"
            shift
            ;;
        -f|--values)
            VALUES_FILE="$2"
            shift 2
            ;;
        -u|--upgrade)
            UPGRADE=true
            shift
            ;;
        -d|--delete)
            DELETE=true
            shift
            ;;
        -s|--status)
            STATUS=true
            shift
            ;;
        -p|--port-forward)
            PORT_FORWARD=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            print_help
            exit 1
            ;;
    esac
done

# 执行操作
if [ "$DELETE" = true ]; then
    check_prerequisites
    delete_airflow
elif [ "$STATUS" = true ]; then
    check_prerequisites
    show_status
elif [ "$PORT_FORWARD" = true ]; then
    check_prerequisites
    port_forward
elif [ "$UPGRADE" = true ]; then
    check_prerequisites
    create_namespace
    upgrade_airflow
    echo ""
    show_status
    echo ""
    echo -e "${GREEN}提示: 使用 '$0 -p' 启动端口转发访问 Web UI${NC}"
else
    check_prerequisites
    create_namespace
    deploy_airflow
    echo ""
    show_status
    echo ""
    echo -e "${GREEN}部署完成！${NC}"
    echo ""
    echo "下一步:"
    echo "  1. 查看 Pod 状态: kubectl get pods -n $NAMESPACE"
    echo "  2. 启动端口转发: $0 -p"
    echo "  3. 获取管理员密码: $0 --get-password (或查看 secret)"
    echo "  4. 访问 Web UI: http://localhost:8080"
fi

