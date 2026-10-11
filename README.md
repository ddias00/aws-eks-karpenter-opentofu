# aws-eks-karpenter-opentofu

Projeto de referência para AWS: VPC em três zonas, EKS, Karpenter e um serviço HTTP com alta disponibilidade. A infraestrutura é criada em três estados independentes para evitar dependências de providers e CRDs durante o primeiro plano.

## Arquitetura

- `infra/`: três subnets privadas, três públicas, NAT por zona, EKS, grupo gerenciado de três nós para componentes de sistema, IAM Pod Identity e fila de interrupções do Karpenter.
- `platform/`: dois controllers Karpenter no grupo de sistema e metrics-server para HPA.
- `workloads/`: EC2NodeClass, NodePool On-Demand e nginx com pelo menos três réplicas, distribuição entre três zonas e nós, probes, PDB e HPA de 3 a 12 pods.

O serviço usa ClusterIP. O acesso de demonstração é via port-forward; exposição pública com TLS exige configurar um ingress/load balancer e domínio. Karpenter escala nós; HPA escala pods. O limite de 100 vCPUs limita o NodePool, mas não é um teto financeiro rígido.

## Pré-requisitos

OpenTofu 1.10+, AWS CLI v2, kubectl e credenciais AWS com permissões para VPC, EKS, EC2, IAM, SQS e EventBridge. A região precisa oferecer três zonas e capacidade para os tipos de instância selecionados. A identidade que executa `infra apply` recebe acesso administrador ao cluster.

Este exemplo gera custos: EKS, três NAT Gateways, nós de sistema, nós Karpenter, tráfego e logs. Não execute apply sem revisar o plano. State local serve para laboratório; para equipe, configure backend S3 criptografado com locking em cada etapa e ajuste os `terraform_remote_state`. Nunca publique states ou credenciais.

## Implantação

Copie `infra/terraform.tfvars.example` para `infra/terraform.tfvars`. Substitua o CIDR de exemplo pelo seu IP público com `/32` e escolha a região. Autentique com seu profile AWS ou SSO (`aws sso login --profile SEU_PROFILE` e variável `AWS_PROFILE`).

Execute da raiz:

```sh
tofu -chdir=infra init
tofu -chdir=infra plan -out=infra.tfplan
tofu -chdir=infra apply infra.tfplan

tofu -chdir=platform init
tofu -chdir=platform plan -out=platform.tfplan
tofu -chdir=platform apply platform.tfplan

tofu -chdir=workloads init
tofu -chdir=workloads plan -out=workloads.tfplan
tofu -chdir=workloads apply workloads.tfplan
```

Configure kubectl (ajuste nome/região se alterou os defaults):

```sh
aws eks update-kubeconfig --name eks-karpenter-demo --region us-east-1
kubectl get nodes -L topology.kubernetes.io/zone,workload
kubectl get nodepool,nodeclaim
kubectl -n ha-demo rollout status deployment/ha-demo
kubectl -n ha-demo get pods -o wide
kubectl -n ha-demo get hpa,pdb
kubectl -n ha-demo port-forward service/ha-demo 8080:80
```

Acesse http://localhost:8080. Confira se existem três pods Ready distribuídos por três zonas. Use `kubectl describe nodepool demo` e logs `kubectl -n kube-system logs -l app.kubernetes.io/name=karpenter --tail=100` para diagnosticar provisionamento. O primeiro rollout aguarda criação de nós e reconciliação do HPA.

## Verificar disponibilidade

Em ambiente de teste, escolha um nó com `workload=demo` e execute `kubectl drain NOME_DO_NO --ignore-daemonsets --delete-emptydir-data`. O PDB mantém pelo menos dois pods durante interrupções voluntárias. Verifique substituição dos pods e criação de capacidade pelo Karpenter; depois execute `kubectl uncordon NOME_DO_NO` se o nó ainda existir. Port-forward usa um único pod e pode desconectar quando esse pod termina; teste continuidade a partir de outro pod usando o DNS `ha-demo.ha-demo.svc.cluster.local`.

Distribuição por zona reduz impacto de falhas; não garante ausência de interrupções. O PDB não protege contra falhas involuntárias. Durante indisponibilidade de uma zona, a restrição de três domínios pode manter substituições Pending, enquanto réplicas nas zonas saudáveis continuam atendendo. Para produção, valide capacidade, observabilidade, TLS, backups e políticas de acesso. Fixe uma release AL2023 em `ami_alias` (o default `al2023@latest` é apenas para laboratório), digests de imagens e versões de addons antes de upgrades.

## Remoção

Mantenha o controller Karpenter ativo até os NodeClaims desaparecerem:

```sh
tofu -chdir=workloads destroy
kubectl get nodeclaims # aguarde até não haver recursos
tofu -chdir=platform destroy
tofu -chdir=infra destroy
```

Não remova a plataforma antes dos nós Karpenter: o controller precisa finalizar as instâncias. Confira no EC2/VPC se os recursos foram removidos.

## Validação e GitHub

`tofu fmt -check -recursive` e `tofu validate` em cada diretório. O workflow valida sem credenciais e não implanta recursos. Commit os arquivos `.terraform.lock.hcl` gerados por `init`; eles fixam providers. Para publicar, crie um repositório no GitHub e faça o push destes arquivos. A implantação real e os testes de falha precisam de uma conta AWS.

Referências: [módulo EKS](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v21.4.0), [Karpenter](https://karpenter.sh/docs/), [topology spread](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/).
