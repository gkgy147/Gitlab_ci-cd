# Gitlab_ci-cd
This is a personal project demonstrating the complete gitlab ci and using argo-cd for deployments. Inside a GKE private cluster made using terraform.

1. Terraform init and apply, explain the cluster configuration.
2. Have the domain hosted in cloudfare and then create a token with dns permissions and install external dns for cloudfare.
 ```
kubectl apply -f- <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: default
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.k8s.io/external-dns/external-dns:v0.13.5
        args:
        - --source=ingress # ingress is also possible
        - --domain-filter=devopsisfun.com
        - --provider=cloudflare
        - --cloudflare-proxied # (optional) enable the proxy feature of Cloudflare (DDOS protection, CDN...)
        - --cloudflare-dns-records-per-page=5000 # (optional) configure how many DNS records to fetch per request
        env:
          - name: CF_API_TOKEN
            value: "1b7olWb2LmdOIssl8-67J6xPvxjOUyEMcU-yQzy4"
          - name: FREE_TIER
            value: "true"


EOF
```
3. create a values.yaml file with the following values 
	add the follwinnghelm repo:
	- helm repo add jetstack https://charts.jetstack.io
 ```
installCRDs: false
replicaCount: 2
extraArgs:
  - --dns01-recursive-nameservers=1.1.1.1:53,9.9.9.9:53
  - --dns01-recursive-nameservers-only
podDnsPolicy: None
podDnsConfig:
  nameservers:
    - "1.1.1.1"
    - "9.9.9.9"
```
5. Installing Certmanager 
  ```
  helm upgrade --install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.11.0 \
  --set installCRDs=true \
  --values=values.yaml \
  --create-namespace

```

6. Installing Nginx-ingress 
```
helm repo add ingress-nginx
https://kubernetes.github.io/ingress-nginx
helm template ingress-nginx ingress-nginx \
--repo https://kubernetes.github.io/ingress-nginx \
--version ${CHART_VERSION} \
--namespace ingress-nginx > nginxingress.yaml
   
```
```
kubectl create ns ingress-nginx 
kubectl apply -f nginxingress.yaml 
```

7. Create the cloudefare api secret in the cluster to issue certificate.
```
kubectl apply -f secret-cf-token.yaml
```
```
kubectl apply -f letsencrypt-staging.yaml
kubectl apply -f letsencrypt-production.yaml
```

```
➜  issuer cat letsencrypt-production.yaml 
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: georgerobert147@gmail.com
    privateKeySecretRef:
      name: letsencrypt-production
    solvers:
      - dns01:
          cloudflare:
            email: georgerobert147@gmail.com
            apiTokenSecretRef:
              name: cloudflare-token-secret
              key: cloudflare-token
        selector:
          dnsZones:
            - "devopsisfun.com"
➜  issuer cat letsencrypt-staging.yaml 
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: georgerobert147@gmail.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - dns01:
          cloudflare:
            email: georgerobert147@gmail.com
            apiTokenSecretRef:
              name: cloudflare-token-secret
              key: cloudflare-token
        selector:
          dnsZones:
            - "devopsisfun.com"
```
8. kubectl get clusterissuer to see if its created.

9. But for gke cluster if we are using the kubernetes nginx ingress controller or gce we get certificate managed by goole itself which is a very nice feature of google. So you dont have to create certificate and store it. I just got to know about because when I created ingress simple and accceeced it it was already https and the certificate was issued by google.  Here is how I ended up with it. By default when we simply deploy the image by pulling it from the container registry it doesnt assign the specic port to access the application so always make sure the port is specified as port because thats where the nginx ingress control listens to.
```
kubectl create deployment python-webapp --image=asia-southeast1-docker.pkg.dev/devopsisfun/pythonwebapp/pythonapp:v1.0
```
   
```
apiVersion: apps/v1
kind: Deployment
metadata:
annotations:
    deployment.kubernetes.io/revision: "2"
  creationTimestamp: "2023-07-11T04:42:36Z"
  generation: 2
  labels:
    app: python-webapp
  name: python-webapp
  namespace: default
  resourceVersion: "211973"
  uid: 4c7a8d7e-be03-481b-aa4a-c541a994f6f9
spec:
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: python-webapp
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      creationTimestamp: null
      labels:
	app: python-webapp
    spec:
      containers:
      - image: asia-southeast1-docker.pkg.dev/devopsisfun/pythonwebapp/pythonapp:v1.0
        imagePullPolicy: IfNotPresent
        name: pythonapp
        ports:
        - containerPort: 80
          protocol: TCP
        resources: {}
        terminationMessagePath: /dev/termination-log
```

the create a yaml for service and ingress :
```
---
apiVersion: v1
kind: Service
metadata:
  name: pythonsvc
spec:
  selector:
    app: python-webapp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 5000


```

```
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pythonweb
  namespace: default
spec:
  ingressClassName: nginx
  rules:
    - host: python.devopsisfun.com
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: pythonsvc
              port:
                number: 80
```

10. Now the application is ready to be acceced from the give hostname.
11. Next step is to deploy a gitlab runner and argocd to complete these ci/cd pipleline.
12. Argo-cd
```
kubectl create namespace argocd kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
To acccess the gui in local host.
```
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

Application configurationwhich we have to apply in kubernetes cluster to initiate tracking the repo we want and also link the target repo with argo-cd give the uid and access token to link with the target deployment repo.
```
---

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: python-webapp
spec:
  project: default
  source:
    repoURL: https://gitlab.com/georgerobert147/deployment.git
    targetRevision: HEAD
    path: dev
  destination: 
    server: https://kubernetes.default.svc
    namespace: default

  syncPolicy:
    syncOptions:
    - CreateNamespace=true

    automated:
      selfHeal: true
      prune: true
```

Now argo-cd will start tracking the maifest yaml and reconcile the kubernetes pod states to the desired state always.

13. Gitlab-runner
```
helm install gitlab-runner --namespace gitlab-runner -f runner.yaml gitlab/gitlab-runner
```
runner.yaml
```
replicas: 1
gitlabUrl: https://gitlab.com/
runnerRegistrationToken: "glrt-Rde_5LKJSxsej7X8vH_m"
concurrent: 10
logLevel: info
logFormat: json
rbac:
 create: true
namespace: gitlabrunner
podLabels: { run: gitlab-ci }
runners:
 privileged: true
```

***TO BE CONTINUED***
