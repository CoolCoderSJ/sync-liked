# Sync Liked Songs

This project synchronizes your liked songs on Spotify to a playlist. It uses Sinatra for the web server, MongoDB for storing access tokens, and Rufus-Scheduler for periodic synchronization.

## Prerequisites

- Docker
- Docker Compose

## Setup

1. Clone the repository:
    ```sh
    git clone https://github.com/CoolCoderSJ/sync-liked.git
    cd sync-liked
    ```

2. Update the `docker-compose.yml` file to include your Spotify credentials:
    ```yaml
    version: '3'
    services:
      app:
        environment:
          - SPOTIFY_CLIENT_ID=your_spotify_client_id
          - SPOTIFY_CLIENT_SECRET=your_spotify_client_secret
          - BASE_URL=your_base_url
          - MONGODB_URI=mongodb://root@example:db:27017/sync-liked?authSource=admin
    ```

3. Start the services using Docker Compose:
    ```sh
    docker-compose up -d
    ```

## Usage

1. Open your browser and navigate to `http://localhost:9373`. You will be redirected to Spotify for authorization.
2. After authorizing, your liked songs will be synchronized to a playlist every hour.

If you wish to stop syncing for just your user, visit `http://localhost:9373/stop` to remove your information from the database. NOTE: Deleting a playlist will not stop the service. However, if you do accidentally delete the playlist, there is latency in the service, so it will take a few hours to recreate the playlist. It is best to visit `/stop` then `/` to reset.

## Stopping the Service

To stop the service, run:
```sh
docker-compose down
```