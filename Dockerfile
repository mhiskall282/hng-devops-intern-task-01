# Use an official lightweight HTTP server as the base image
FROM nginx:alpine
# Copy a simple index.html file to serve
COPY index.html /usr/share/nginx/html/
# The default Nginx port (80) is exposed
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
