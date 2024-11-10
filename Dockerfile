FROM ruby:slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    libcurl4-openssl-dev \
    pkg-config

COPY Gemfile Gemfile.lock ./

RUN bundle install

COPY . .

EXPOSE 9373

CMD ["bundle", "exec", "ruby", "server.rb"]