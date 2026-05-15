# DevOps Practice Guide & Implementation Plan

This guide is tailored specifically for your `antirag` mini-project. It outlines exactly how to accomplish the 5 steps required for your hands-on exam. 

> [!IMPORTANT]
> Since you have an exam today, this guide is designed to be highly detailed so you can follow it step-by-step. Let me know if you would like me to automatically generate the GitHub Actions workflow and deployment scripts for you to speed up your practice.

---

## Step 1: Host Your Application on GitHub (Git)

First, we need to push your local `antirag` codebase to a remote GitHub repository. This is the foundation for our CI/CD pipeline.

1. **Create a new repository on GitHub:**
   - Go to [GitHub](https://github.com/) and create a new repository (e.g., `antirag-devops`). Do not initialize it with a README or .gitignore (you already have one).

2. **Initialize and Push your local code:**
   Open your terminal in the `antirag` folder and run:
   ```bash
   git init
   git add .
   git commit -m "Initial commit of antirag project"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/antirag-devops.git
   git push -u origin main
   # if error will come like branch 'main' set up to track 'origin/main'.
   git remote set-url origin https://github.com/YOUR_USERNAME/antirag-devops.git
   git push -u origin main
   ```

---

## Step 2: Manually Deploy Your Application on an AWS EC2 Instance

This step covers launching a server and setting up the application manually.

### 1. Launch the EC2 Instance
- Go to the AWS Management Console -> **EC2** -> **Launch Instance**.
- **Name:** `antirag-server-1`
- **AMI:** Ubuntu Server 24.04 LTS
- **Instance Type:** t2.micro (Free Tier eligible)
- **Key Pair:** Create a new key pair (e.g., `antirag-key.pem`) and download it.
- **Network Settings (Security Group):**
  - Allow **SSH traffic** from anywhere.
  - Allow **HTTP traffic** from the internet.
  - Allow **Custom TCP** on port `8000` (for your backend API) from the internet.
  - Allow **Custom TCP** on port `5173` (for frontend preview) from the internet.
- **Configure Storage:** Change the default `8 GiB` to **`15 GiB`**. *(This prevents the "No space left on device" error during NPM install and gives plenty of room for your Swap space!)*

### 2. Connect to Your Instance
Open your terminal where your `.pem` file is located:
```bash
# Set permissions for your key (macOS/Linux only, not needed on Windows command prompt)
chmod 400 antirag-key.pem

# SSH into the instance
ssh -i "antirag-key.pem" ubuntu@<YOUR_EC2_PUBLIC_IP>
```

### 3. Install Dependencies and Clone Repo
Once inside the EC2 terminal, run:
```bash
# Update packages
sudo apt update && sudo apt upgrade -y

# Install Node.js & npm
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install Python 3, pip, Nginx, and essential C/Rust compilers (Prevents build errors!)
sudo apt install -y python3-pip python3-venv python3-dev build-essential libpq-dev cargo nginx

# Install PM2 (Process Manager to keep the app running forever)
sudo npm install -g pm2

# Clone your repository
git clone https://github.com/YOUR_USERNAME/antirag-devops.git
cd antirag-devops
```

### 4. Run the Backend & Frontend using PM2
We will use PM2 to keep both the React Vite frontend and the Python FastAPI backend running in the background.

```bash
# ---- Add Swap Space (CRITICAL for 1GB RAM EC2 Instances to prevent Out of Memory errors) ----
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# ---- Start Backend ----
cd backend
python3 -m venv venv
source venv/bin/activate

# Upgrade pip/wheel to prevent metadata errors
pip install --upgrade pip setuptools wheel

# Install dependencies (will now compile flawlessly!)
pip install -r requirements.txt --no-cache-dir

# Start Uvicorn with PM2
pm2 start "uvicorn main:app --host 0.0.0.0 --port 8000" --name "antirag-backend"

# ---- Start Frontend ----
cd ../frontend
npm install
npm run build
# Start Vite Preview with PM2 (or serve build folder using serve)
sudo npm install -g serve
pm2 start "serve -s dist -l 5173" --name "antirag-frontend"

# Generate PM2 startup script
pm2 startup
# IMPORTANT: The terminal will print a line starting with "sudo env PATH...".
# You MUST copy and paste that line into the terminal and run it!

# After running the sudo command, save the PM2 configuration
pm2 save
```

---

## Step 3: Deploy Application on an EC2 Instance (Routing via Nginx)

To access your app without typing port numbers (e.g., `http://<IP>`), we configure Nginx.

1. **Edit Nginx Config:**
   ```bash
   sudo nano /etc/nginx/sites-available/default
   ```
2. **Replace the content with:**
   ```nginx
   server {
       listen 80 default_server;

       # Frontend Route
       location / {
           proxy_pass http://localhost:5173;
       }

       # Backend API Route
       location /api/ {
           proxy_pass http://localhost:8000/;
       }
   }
   ```
3. **Restart Nginx:**
   ```bash
   sudo systemctl restart nginx
   ```
Now your app is fully hosted on `http://<YOUR_EC2_PUBLIC_IP>`.

---

## Step 4: Deploy using an Application Load Balancer (ALB) for High Availability

To ensure your app stays up even if one server crashes, we use an ALB.

1. **Create a Second EC2 Instance:**
   - Go to your running `antirag-server-1` in AWS.
   - Select it -> **Actions** -> **Image and templates** -> **Create image**.
   - Use this custom AMI to launch a second instance (`antirag-server-2`). This guarantees the new server has your code, PM2, and Nginx perfectly configured.
2. **Create a Target Group:**
   - In AWS Console, go to **EC2** -> **Target Groups** (under Load Balancing).
   - Create a new target group. Choose **Instances**. Set Protocol to HTTP, Port 80.
   - Register both `antirag-server-1` and `antirag-server-2` as targets.
3. **Create the Load Balancer:**
   - Go to **EC2** -> **Load Balancers** -> **Create Load Balancer** -> **Application Load Balancer**.
   - Make it **Internet-facing**. Select at least two subnets (Availability Zones).
   - Under Listeners and Routing, forward HTTP (Port 80) traffic to the Target Group you just created.
4. **Access your App:** Once provisioned, use the Load Balancer's DNS name (e.g., `my-alb-12345.us-east-1.elb.amazonaws.com`) to access your app. The ALB will automatically split traffic between both EC2 instances.

---

## Step 5: Automate Deployment using GitHub Actions (CI/CD)

Instead of SSHing into your servers every time you make a code change, we will create a GitHub Actions workflow.

### 1. Add GitHub Secrets
Go to your GitHub Repository -> **Settings** -> **Secrets and variables** -> **Actions** -> **New repository secret**. Add the following:
- `HOST_1`: Public IP of `antirag-server-1`
- `HOST_2`: Public IP of `antirag-server-2`
- `USERNAME`: `ubuntu`
- `SSH_KEY`: The raw text content of your `antirag-key.pem` file.

### 2. Create the Workflow File
In your local project, create `.github/workflows/deploy.yml` with a script to SSH into the instances, pull the latest code, and restart PM2.

> [!TIP]
> **Action Required**: Before you take your exam, would you like me to go ahead and generate the `.github/workflows/deploy.yml` and `deploy.sh` files for you right now so you have the exact code ready to commit?
