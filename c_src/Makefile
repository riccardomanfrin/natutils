ERLPATH=$(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version)])])' -s init stop -noshell)
INCLUDEPATH=$(ERLPATH)/include
LIBPATH=$(ERLPATH)/../usr/lib/
ROOTPATH=$(shell pwd)/../

$(ROOTPATH)priv/route_table.so: route_table.c
	mkdir -p $(ROOTPATH)priv/
	gcc -fPIC -shared -o $(ROOTPATH)priv/route_table.so -I $(INCLUDEPATH) -g -ggdb -L $(LIBPATH) -lei  route_table.c