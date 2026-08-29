git pull
npm --prefix frontend run build
git add frontend/dist
git commit -m "Build frontend"
git push
