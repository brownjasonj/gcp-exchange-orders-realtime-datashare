#include <crow.h>

struct CORSMiddleware {
    struct context {};

    void before_handle(crow::request& req, crow::response& res, context& /*ctx*/) {
        if (req.method == crow::HTTPMethod::Options) {
            res.code = 200;
            res.add_header("Access-Control-Allow-Origin", "*");
            res.add_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE");
            res.add_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With");
            res.end();
        }
    }

    void after_handle(crow::request& req, crow::response& res, context& /*ctx*/) {
        res.add_header("Access-Control-Allow-Origin", "*");
        res.add_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE");
        res.add_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With");
    }
};

int main() {
    crow::App<CORSMiddleware> app;

    CROW_ROUTE(app, "/api/test")
    .methods("POST"_method, "OPTIONS"_method)
    ([]() {
        return "OK";
    });

    CROW_CATCHALL_ROUTE(app)
    ([](crow::response& res) {
        res.code = 200;
        res.end();
    });

    app.port(18080).run();
}
