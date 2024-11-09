FROM ruby:slim

WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN gem install bundler && bundle install

COPY . .

EXPOSE 9373

CMD ["ruby", "server.rb"]