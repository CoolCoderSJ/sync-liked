require 'sinatra'
require 'httparty'
require 'mongo'

set :port, 9373
BASE = ENV['BASE_URL']

client = Mongo::Client.new(ENV['MONGO_URI'])
db = client.database
col = db[:access_tokens]

get '/' do
    redirect "https://accounts.spotify.com/authorize?response_type=code&client_id=#{ENV['SPOTIFY_CLIENT_ID']}&scope=user-library-read%20playlist-read-private%20playlist-modify-public%20playlist-modify-private&redirect_uri=#{BASE}/callback"
end

get '/stop' do
    redirect "https://accounts.spotify.com/authorize?response_type=code&client_id=#{ENV['SPOTIFY_CLIENT_ID']}&redirect_uri=#{BASE}/handle_stop"
end

get '/handle_stop' do
    code = params[:code]
    response = HTTParty.post('https://accounts.spotify.com/api/token', {
        body: {
            grant_type: 'authorization_code',
            code: code,
            redirect_uri: "#{BASE}/handle_stop",
        },
        headers: {
            'Authorization' => 'Basic ' + Base64.strict_encode64("#{ENV['SPOTIFY_CLIENT_ID']}:#{ENV['SPOTIFY_CLIENT_SECRET']}"),
            "Content-Type" => "application/x-www-form-urlencoded"
        }
    })
    access_token = response['access_token']
    refresh_token = response['refresh_token']
    response = HTTParty.get('https://api.spotify.com/v1/me', {
        headers: {
            "Authorization" => "Bearer #{access_token}"
        }
    })
    user_id = response['id']
    col.find_one_and_delete({_id: user_id})
    "Your access token has been deleted. You can now close this window."
end

get '/callback' do
    code = params[:code]
    response = HTTParty.post('https://accounts.spotify.com/api/token', {
        body: {
            grant_type: 'authorization_code',
            code: code,
            redirect_uri: "#{BASE}/callback",
        },
        headers: {
            'Authorization' => 'Basic ' + Base64.strict_encode64("#{ENV['SPOTIFY_CLIENT_ID']}:#{ENV['SPOTIFY_CLIENT_SECRET']}"),
            "Content-Type" => "application/x-www-form-urlencoded"
        }
    })
    access_token = response['access_token']
    refresh_token = response['refresh_token']
    # get user id
    response = HTTParty.get('https://api.spotify.com/v1/me', {
        headers: {
            "Authorization" => "Bearer #{access_token}"
        }
    })
    user_id = response['id']
    col.find_one_and_update({_id: user_id}, {"$set" => {access_token: access_token, "refresh_token": refresh_token}}, {upsert: true})

    "Your access token has been saved and a sync job will start within an hour. You can now close this window. #{access_token}"
end


require 'tzinfo/data'
require 'rufus-scheduler'
scheduler = Rufus::Scheduler.new

scheduler.every '1h' do
client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'sync-liked')
db = client.database
col = db[:access_tokens]


col.find.each do |doc|
    access_token = doc[:access_token]
    refresh_token = doc[:refresh_token]

    response = HTTParty.get('https://api.spotify.com/v1/me', {
        headers: {
            "Authorization" => "Bearer #{access_token}"
        }
    })
    if response.code == 401
        response = HTTParty.post('https://accounts.spotify.com/api/token', {
            body: {
                "grant_type" => 'refresh_token',
                "refresh_token" => refresh_token,
            }.to_json,
            headers: {
                "Content-Type" => "application/x-www-form-urlencoded"
            }
        })
        access_token = response['access_token']
        refresh_token = response['refresh_token']
        col.find_one_and_update({_id: doc[:_id]}, {"$set" => {access_token: access_token, "refresh_token": refresh_token}}, {upsert: true})
    end

    tracks = []
    offset = 0
    while true do
        response = HTTParty.get("https://api.spotify.com/v1/me/tracks?offset=#{offset}&limit=50", {
            headers: {
                "Authorization" => "Bearer #{access_token}"
            }
        })
        begin 
            tracks += response['items']
        rescue
            puts response
            break
        end
        if response['next'] == nil
            break
        else
            offset += 50
        end
    end

    tracks = tracks.map{|track| track['track']['uri']}
    puts "Found #{tracks.length} songs in current liked songs"
    tracks = tracks.each_slice(100).to_a

    if doc[:playlist_id] != nil
        response = HTTParty.get("https://api.spotify.com/v1/playlists/#{doc[:playlist_id]}", {
            headers: {
                "Authorization" => "Bearer #{access_token}"
            }
        })
        if response.code == 404
            puts "playlist not found, creating new one"
            doc[:playlist_id] = nil
        end
    end

    if doc[:playlist_id] != nil
        inPlaylist = []
        offset = 0
        while true do
            response = HTTParty.get("https://api.spotify.com/v1/playlists/#{doc[:playlist_id]}/tracks?offset=#{offset}&limit=50", {
                headers: {
                    "Authorization" => "Bearer #{access_token}"
                }
            })
            inPlaylist += response['items']
            if response['next'] == nil
                break
            else
                offset += 50
            end
        end

        puts "Found #{inPlaylist.length} songs in current playlist"

        playlist = HTTParty.get("https://api.spotify.com/v1/playlists/#{doc[:playlist_id]}", {
            headers: {
                "Authorization" => "Bearer #{access_token}"
            }
        })

        allUri = inPlaylist.map{|track| track['track']['uri']}
        allUri = allUri.each_slice(100).to_a

        allUri.each_with_index do |uri_chunk, index|
            HTTParty.delete("https://api.spotify.com/v1/playlists/#{doc[:playlist_id]}/tracks", {
                body: {
                    "tracks" => uri_chunk.map{|uri| {uri: uri}},
                    "snapshot_id" => playlist['snapshot_id']
                }.to_json,
                headers: {
                    "Authorization" => "Bearer #{access_token}",
                    "Content-Type" => "application/json"
                }
            })
        end
    else
        puts "creating playlist for #{doc[:_id]}"
        playlist = HTTParty.post("https://api.spotify.com/v1/users/#{doc[:_id]}/playlists", {
            body: {
                "name" => "Liked Songs"
            }.to_json,
            headers: {
                "Authorization" => "Bearer #{access_token}",
                "Content-Type" => "application/json"
            }
        })
        doc[:playlist_id] = playlist['id']
        col.find_one_and_update({_id: doc[:_id]}, {"$set" => {playlist_id: playlist['id']}})
    end

    puts "Adding songs to playlist #{doc[:playlist_id]}"

    tracks.each_with_index do |track_chunk, index|
        HTTParty.post("https://api.spotify.com/v1/playlists/#{doc[:playlist_id]}/tracks", {
            body: {
                "uris" => track_chunk
            }.to_json,
            headers: {
                "Authorization" => "Bearer #{access_token}",
                "Content-Type" => "application/json"
            }
        })
    end

end
end

Thread.new { scheduler.join }