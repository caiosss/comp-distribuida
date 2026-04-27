from locust import HttpUser, task, between

class WebsiteUser(HttpUser):
    wait_time = between(1, 3)

    # @task
    # def index(self):
    #     self.client.get("/")

    @task
    def post_page(self):
        self.client.get("/?p=1")