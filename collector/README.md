# QUEUE SETUP 
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# QUEUE CONFIGURATION
sudo rabbitmqctl add_user admin admin
sudo rabbitmqctl set_user_tags admin administrator
sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"

# Enable management dashboard
sudo rabbitmq-plugins enable rabbitmq_management


# Access via:

http://localhost:15672
user: guest
pass: guest

This dashboard lets you watch queues, messages, and consumers in real time.

