pipeline {
    agent any

    environment {
        AWS_REGION   = 'us-east-1'
        CLUSTER_NAME = 'secure-eks-dev-cluster'
        APP_NAME     = 'secure-eks-demo'
        K8S_NAMESPACE = 'default'
        KUBECONFIG   = "${WORKSPACE}/.kube/config"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Test Application') {
            steps {
                sh '''
                    python3 -m py_compile app/app.py
                    echo "Application syntax validation passed."
                '''
            }
        }

        stage('AWS Identity') {
            steps {
                sh '''
                    aws sts get-caller-identity
                '''
            }
        }

        stage('EKS Authentication') {
            steps {
                sh '''
                    mkdir -p "$(dirname "$KUBECONFIG")"

                    aws eks update-kubeconfig \
                      --region "$AWS_REGION" \
                      --name "$CLUSTER_NAME" \
                      --kubeconfig "$KUBECONFIG"

                    kubectl auth can-i patch deployments \
                      --namespace "$K8S_NAMESPACE"
                '''
            }
        }
    }
}
