#!bin/bash

sudo snap remove google-cloud-cli --no-wait


sudo apt update
sudo apt install apt-transport-https ca-certificates gnupg curl sudo -y

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update
sudo apt install google-cloud-cli -y

sudo apt install google-cloud-sdk-gke-gcloud-auth-plugin kubectl helm -y

sudo kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null

sudo helm completion bash > /etc/bash_completion.d/helm

sudo chmod a+r /etc/bash_completion.d/kubectl /etc/bash_completion.d/helm

