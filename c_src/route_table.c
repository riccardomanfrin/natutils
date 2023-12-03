/*
 *
 */
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/types.h>
#include <unistd.h>
#include <time.h>
#include <stdio.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <linux/rtnetlink.h>

#include <erl_nif.h>

#define MAXROUTES 100

struct route{
    uint8_t family;
    char src[16];
    char net[16];
    int mask;
    char via[16];
    char dev[15];
};

extern int route_table();

ERL_NIF_TERM addr_to_tuple(ErlNifEnv* env, uint8_t fam, char addr[16]) {
    int i = 0;
    if (fam == AF_INET) {
        ERL_NIF_TERM eaddr[4];
        for (; i < 4; i++) {
            int val = addr[i];
            if (val < 0) {
                val+=256;
            }
            
            eaddr[i] = enif_make_int(env, val);
        }
        return  enif_make_tuple_from_array(env, eaddr, 4);
    } else {
        ERL_NIF_TERM eaddr[16];
        for (; i < 16; i++) {
            eaddr[i] = enif_make_int(env, addr[i]);
        }
        return  enif_make_tuple_from_array(env, eaddr, 16);
    }   
}

static ERL_NIF_TERM route_table_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    int ret;
    struct route routes[MAXROUTES];
    memset(routes, 0, sizeof(struct route) * MAXROUTES);
    ERL_NIF_TERM routes_list[MAXROUTES];
    ERL_NIF_TERM route_keys[4] = {
        enif_make_atom(env, "net"),
        enif_make_atom(env, "mask"),
        enif_make_atom(env, "via"),
        enif_make_atom(env, "dev"),
    };
    ret = route_table(routes);
    int i = 0;
    for(; i < 100; i++) {
        if (routes[i].family > 0) {
            ERL_NIF_TERM route_vals[4];
            
            route_vals[0] = addr_to_tuple(env, routes[i].family, routes[i].net);
            route_vals[1] = enif_make_uint(env, routes[i].mask);
            route_vals[2] = addr_to_tuple(env, routes[i].family, routes[i].via);
            route_vals[3] = enif_make_string(env, routes[i].dev, ERL_NIF_LATIN1);

            enif_make_map_from_arrays(env, route_keys, route_vals, 4, &routes_list[i]);
        } else {
            break;
        }

    }
    return enif_make_list_from_array(env, routes_list, i);
}

static ErlNifFunc nif_funcs[] =
{
    {"route_table", 0, route_table_nif}
};

ERL_NIF_INIT(Elixir.Utils, nif_funcs,NULL,NULL,NULL,NULL);


/****************************************************************/


int rtnl_receive(int fd, struct msghdr *msg, int flags)
{
    int len;

    do { 
        len = recvmsg(fd, msg, flags);
    } while (len < 0 && (errno == EINTR || errno == EAGAIN));

    if (len < 0) {
        perror("Netlink receive failed");
        return -errno;
    }

    if (len == 0) { 
        perror("EOF on netlink");
        return -ENODATA;
    }

    return len;
}

static int rtnl_recvmsg(int fd, struct msghdr *msg, char **answer)
{
    struct iovec *iov = msg->msg_iov;
    char *buf;
    int len;

    iov->iov_base = NULL;
    iov->iov_len = 0;

    len = rtnl_receive(fd, msg, MSG_PEEK | MSG_TRUNC);

    if (len < 0) {
        return len;
    }

    buf = malloc(len);

    if (!buf) {
        perror("malloc failed");
        return -ENOMEM;
    }

    iov->iov_base = buf;
    iov->iov_len = len;

    len = rtnl_receive(fd, msg, 0);

    if (len < 0) {
        free(buf);
        return len;
    }

    *answer = buf;

    return len;
}

void parse_rtattr(struct rtattr *tb[], int max, struct rtattr *rta, int len)
{
    memset(tb, 0, sizeof(struct rtattr *) * (max + 1));

    while (RTA_OK(rta, len)) {
        if (rta->rta_type <= max) {
            tb[rta->rta_type] = rta;
        }

        rta = RTA_NEXT(rta,len);
    }
}

static inline int rtm_get_table(struct rtmsg *r, struct rtattr **tb)
{
    __u32 table = r->rtm_table;

    if (tb[RTA_TABLE]) {
        table = *(__u32 *)RTA_DATA(tb[RTA_TABLE]);
    }

    return table;
}

int print_route(struct nlmsghdr* nl_header_answer, struct route *rt)
{
    
    struct rtmsg* r = NLMSG_DATA(nl_header_answer);
    int len = nl_header_answer->nlmsg_len;
    struct rtattr* tb[RTA_MAX+1];
    int table;
    char buf[256];

    len -= NLMSG_LENGTH(sizeof(*r));

    if (len < 0) {
        perror("Wrong message length");
        return -1;
    }
    
    parse_rtattr(tb, RTA_MAX, RTM_RTA(r), len);

    table = rtm_get_table(r, tb);

    if (r->rtm_family != AF_INET && table != RT_TABLE_MAIN) {
        return -1;
    }

    if (tb[RTA_DST]) {
        if ((r->rtm_dst_len != 24) && (r->rtm_dst_len != 16)) {
            return -1;
        }
        rt->family = r->rtm_family;
        if (rt->family == AF_INET) {
            memcpy(rt->net, RTA_DATA(tb[RTA_DST]), 4);
        } else if (rt->family == AF_INET6) {
            memcpy(rt->net, RTA_DATA(tb[RTA_DST]), 16);
        }
        rt->mask = r->rtm_dst_len;
    } else if (r->rtm_dst_len) {
        rt->mask = r->rtm_dst_len;
    } else {
        rt->family = r->rtm_family;
        rt->mask = 0;
    }

    if (tb[RTA_GATEWAY]) {
        if (rt->family == AF_INET) {
            memcpy(rt->via, RTA_DATA(tb[RTA_GATEWAY]), 4);
        } else if (rt->family == AF_INET6) {
            memcpy(rt->via, RTA_DATA(tb[RTA_GATEWAY]), 16);
        }
    }

    if (tb[RTA_OIF]) {
        char if_nam_buf[IF_NAMESIZE];
        int ifidx = *(__u32 *)RTA_DATA(tb[RTA_OIF]);

        sprintf(rt->dev, "%s", if_indextoname(ifidx, if_nam_buf));
    }

    if (tb[RTA_SRC]) {
        sprintf(rt->src, "%s", inet_ntop(r->rtm_family, RTA_DATA(tb[RTA_SRC]), buf, sizeof(buf)));
    }

    return 0;
}

int open_netlink()
{
    struct sockaddr_nl saddr;

    int sock = socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE);

    if (sock < 0) {
        perror("Failed to open netlink socket");
        return -1;
    }

    memset(&saddr, 0, sizeof(saddr));

    saddr.nl_family = AF_NETLINK;
    saddr.nl_pid = getpid();

    if (bind(sock, (struct sockaddr *)&saddr, sizeof(saddr)) < 0) {
        perror("Failed to bind to netlink socket");
        close(sock);
        return -1;
    }

    return sock;
}

int do_route_dump_requst(int sock)
{
    struct {
        struct nlmsghdr nlh;
        struct rtmsg rtm;
    } nl_request;

    nl_request.nlh.nlmsg_type = RTM_GETROUTE;
    nl_request.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    nl_request.nlh.nlmsg_len = sizeof(nl_request);
    nl_request.nlh.nlmsg_seq = time(NULL);
    nl_request.rtm.rtm_family = AF_INET;

    return send(sock, &nl_request, sizeof(nl_request), 0);
}

int get_route_dump_response(int sock, struct route routes[])
{
    struct sockaddr_nl nladdr;
    struct iovec iov;
    struct msghdr msg = {
        .msg_name = &nladdr,
        .msg_namelen = sizeof(nladdr),
        .msg_iov = &iov,
        .msg_iovlen = 1,
    };

    char *buf;
    int dump_intr = 0;

    int status = rtnl_recvmsg(sock, &msg, &buf);

    struct nlmsghdr *h = (struct nlmsghdr *)buf;
    int msglen = status;

    
    int route_id = 0;

    while (NLMSG_OK(h, msglen)) {
        if (h->nlmsg_flags & NLM_F_DUMP_INTR) {
            fprintf(stderr, "Dump was interrupted\n");
            free(buf);
            return -1;
        }

        if (nladdr.nl_pid != 0) {
            continue;
        }

        if (h->nlmsg_type == NLMSG_ERROR) {
            perror("netlink reported error");
            free(buf);
        }

       print_route(h, &routes[route_id]);
       route_id++;

        h = NLMSG_NEXT(h, msglen);
    }

    free(buf);

    return status;
}


int route_table(struct route routes[])
{
    int nl_sock = open_netlink();

    if (do_route_dump_requst(nl_sock) < 0) {
        perror("Failed to perfom request");
        close(nl_sock);
        return -1;
    }

    int res = get_route_dump_response(nl_sock, routes);

    close (nl_sock);

    return res;
}
