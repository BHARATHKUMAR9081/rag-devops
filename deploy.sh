#!/bin/bash

# Navigate to the project directory
cd /home/ubuntu/antirag-devops

# Restart backend
echo "Restarting backend..."
cd backend
source venv/bin/activate
pip install -r requirements.txt --no-cache-dir
pm2 restart antirag-backend

# Restart frontend
echo "Restarting frontend..."
cd ../frontend
npm install
npm run build
pm2 restart antirag-frontend

echo "Deployment complete!"
