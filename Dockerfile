FROM ruby:2.2.2

RUN apt-get update && apt-get install -y redis-server supervisor vim

COPY ./config/feeder.supervisor.conf /etc/supervisor/conf.d/feeder.conf
RUN mkdir -p /usr/src/app/log/
WORKDIR /usr/src/app

COPY Gemfile /usr/src/app/
COPY Gemfile.lock /usr/src/app/
RUN bundle install

COPY . /usr/src/app

EXPOSE 3000
EXPOSE 6379

#CMD ["/usr/bin/supervisord","-c","/etc/supervisor/supervisord.conf"]
#CMD ["/usr/bin/redis-server"]
#CMD ["/usr/local/bundle/bin/bundle","exec","rake","save_feeds"]
#CMD ["clockwork", "schedule.rb"]
