FROM ruby:slim

WORKDIR /app

COPY . .

RUN bundle install

EXPOSE 9373

CMD ["ruby", "server.rb"]