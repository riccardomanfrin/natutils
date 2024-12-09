FROM elixir:1.16.1-slim as build

COPY . /app
WORKDIR /app
RUN apt update
RUN apt install make gcc -y
RUN mix local.hex --force
RUN mix deps.get
RUN mix release

FROM elixir:1.16.1-slim as run
COPY --from=build /app /app
WORKDIR /app
CMD _build/dev/rel/natutils/bin/natutils start