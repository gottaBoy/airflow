# Airflow Helm Chart 部署指南

## 快速部署

```bash
# 1. 创建命名空间
kubectl create namespace airflow

# 2. 安装（默认配置）
helm install airflow . --namespace airflow

# 3. 启用示例 DAGs
helm install airflow . --namespace airflow \
  --set-string "env[0].name=AIRFLOW__CORE__LOAD_EXAMPLES" \
  --set-string "env[0].value=True"
```

## 检查部署状态

```bash
# 查看 Helm release
helm list -n airflow
helm status airflow -n airflow

# 查看 Pods
kubectl get pods -n airflow

# 查看所有资源
kubectl get all -n airflow

# 查看 Pod 状态详情
kubectl get pods -n airflow -o wide

# 检查关键组件
kubectl get deployment -n airflow
kubectl get svc -n airflow
```

## 访问 Web UI

```bash
# 端口转发
kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow

# 获取管理员密码
kubectl get secret airflow-webserver-secret -n airflow \
  -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

访问：http://localhost:8080  
默认用户名：`admin`

## 镜像配置（Airflow 3.1.3）

```yaml
# values.yaml
images:
  airflow:
    repository: apache/airflow
    tag: '3.1.3'
    pullPolicy: IfNotPresent
```

**使用国内镜像源（网络问题时）：**
```bash
helm install airflow . --namespace airflow \
  --set images.airflow.repository=registry.cn-hangzhou.aliyuncs.com/google_containers/apache-airflow \
  --set images.airflow.tag=3.1.3

helm install airflow . --namespace airflow \
  --set images.airflow.repository=harbor.intra.zeron.ai/library/airflow \
  --set images.airflow.tag=3.1.5
```

## 常见问题

### 1. 镜像拉取失败 (ImagePullBackOff)

**错误：** `connection timed out` 或 `ErrImagePull`

**解决：**
```bash
# 方案1：使用国内镜像源
helm uninstall airflow -n airflow
helm install airflow . --namespace airflow \
  --set images.airflow.repository=registry.cn-hangzhou.aliyuncs.com/google_containers/apache-airflow \
  --set images.airflow.tag=3.1.3 \
  --set images.airflow.pullPolicy=Always

# 方案2：节点上手动拉取后使用 Never
# 在节点上执行：docker pull apache/airflow:3.1.3
helm install airflow . --namespace airflow \
  --set images.airflow.pullPolicy=Never
```

### 2. Release 名称冲突

```bash
helm uninstall airflow -n airflow
helm install airflow . --namespace airflow
```

### 3. Pod 无法启动

```bash
# 查看详情
kubectl describe pod <pod-name> -n airflow

# 查看日志
kubectl logs <pod-name> -n airflow

# 查看事件
kubectl get events -n airflow --sort-by='.lastTimestamp'
```

### 4. 数据库连接失败

```bash
# 检查数据库服务
kubectl get svc -n airflow | grep postgres

# 测试连接
kubectl exec -it deployment/airflow-scheduler -n airflow -- airflow db check
```

## 常用操作

### 升级部署

```bash
helm upgrade airflow . --namespace airflow

# 升级并修改配置
helm upgrade airflow . --namespace airflow \
  --set images.airflow.tag=3.1.4
```

### 回滚

```bash
helm history airflow -n airflow
helm rollback airflow <revision-number> -n airflow
```

### 卸载

```bash
helm uninstall airflow -n airflow
```

### 查看配置

```bash
helm get values airflow -n airflow
helm get values airflow -n airflow --all
```

### 查看日志

```bash
# 调度器
kubectl logs -f deployment/airflow-scheduler -n airflow

# Web Server
kubectl logs -f deployment/airflow-api-server -n airflow
```

## 配置执行器

```bash
# LocalExecutor
helm install airflow . --namespace airflow \
  --set executor=LocalExecutor

# CeleryExecutor
helm install airflow . --namespace airflow \
  --set executor=CeleryExecutor
```

## 使用自定义 values 文件

```bash
# 1. 复制并编辑
cp values.yaml my-values.yaml

# 2. 安装
helm install airflow . --namespace airflow -f my-values.yaml
```

## PostgreSQL 存储配置

**配置位置：** `values.yaml` 第 2968-2981 行

```yaml
# values.yaml
postgresql:
  enabled: true
  image:
    repository: bitnami/postgresql
    tag: "13"  # 使用 latest 13 版本，或指定具体标签
    # 如果 Harbor 中有 Bitnami 镜像：
    # registry: harbor.intra.zeron.ai
    # repository: library/postgresql
  primary:
    persistence:
      enabled: true      # 必须启用
      storageClass: ebs-ssd  # 注意：Bitnami chart 使用 storageClass 不是 storageClassName
      size: 20Gi
```

**验证配置是否存在：**
```bash
# 检查 values.yaml 中的配置
grep -A 15 "^postgresql:" values.yaml

# 检查 Helm 实际使用的配置
helm get values airflow -n airflow | grep -A 10 postgresql
```

**让配置生效：**

```bash
# 如果还未部署
helm install airflow . --namespace airflow

# 如果已部署，需要升级
helm upgrade airflow . --namespace airflow

# 如果 PVC 已存在（8Gi），需要删除后重新创建（⚠️ 会丢失数据）
# 1. 先停止 PostgreSQL（删除 StatefulSet）
kubectl delete statefulset airflow-postgresql -n airflow

# 2. 删除现有 PVC
kubectl delete pvc data-airflow-postgresql-0 -n airflow

# 3. 升级部署，会创建新的 20Gi PVC
helm upgrade airflow . --namespace airflow

# 4. 验证 PVC 大小
kubectl get pvc -n airflow | grep postgres
```

## 调试

```bash
# 查看渲染的模板
helm template . --namespace airflow

# 进入 Pod
kubectl exec -it deployment/airflow-scheduler -n airflow -- /bin/bash

# 检查 Airflow 配置
kubectl exec -it deployment/airflow-scheduler -n airflow -- airflow config list

# 检查 PVC 大小
kubectl get pvc -n airflow
```

