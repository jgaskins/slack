FROM 84codes/crystal:1.8.2-alpine AS build

WORKDIR /rex
COPY shard.yml shard.lock .
# RUN shards install -j12

COPY src/ src/
COPY lib/ lib/
RUN mkdir -p bin
RUN crystal build --static -o bin/rex src/rex.cr

CMD ["bin/rex"]

FROM alpine

COPY --from=build /rex/bin/rex .
CMD ["./rex"]
