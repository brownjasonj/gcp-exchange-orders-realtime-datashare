#include "simulator.hpp"
#include <iostream>
#include <fstream>
#include "types.hpp"
#include <nlohmann/json.hpp>
#include <crow.h>

using json = nlohmann::json;

struct CORSMiddleware {
    struct context {};

    void before_handle(crow::request& req, crow::response& res, context& /*ctx*/) {
        if (req.method == crow::HTTPMethod::Options) {
            res.add_header("Access-Control-Allow-Origin", "*");
            res.add_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            res.add_header("Access-Control-Allow-Headers", "Content-Type, Authorization");
            res.code = 204;
            res.end();
        }
    }

    void after_handle(crow::request& /*req*/, crow::response& res, context& /*ctx*/) {
        res.add_header("Access-Control-Allow-Origin", "*");
    }
};

int main(int argc, char* argv[]) {
    // Load config
    std::string config_path = "config.json";
    if (argc > 1) config_path = argv[1];

    std::ifstream f(config_path);
    nlohmann::json config_json;
    if (f.is_open()) {
        f >> config_json;
    } else {
        std::cerr << "Warning: Could not open config file: " << config_path << ", using defaults." << std::endl;
        config_json["symbols"] = {"AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"};
        config_json["currencies"] = {"USD", "EUR"};
        config_json["venues"] = {"NASDAQ", "NYSE"};
    }

    simulator::Config config = config_json.get<simulator::Config>();
    
    // Override with environment variables
    if (const char* proj_id = std::getenv("PROJECT_ID")) config.gcp_project_id = proj_id;
    if (const char* ds_id = std::getenv("BIGQUERY_DATASET_ID")) config.bigquery_dataset_id = ds_id;
    if (const char* tb_id = std::getenv("BIGQUERY_TABLE_ID")) config.bigquery_table_id = tb_id;
    
    // Default values if still empty
    if (config.bigquery_dataset_id.empty()) config.bigquery_dataset_id = "simulator_data";
    if (config.bigquery_table_id.empty()) config.bigquery_table_id = "order_ticks_delay";

    simulator::Simulator sim(config);

    crow::App<CORSMiddleware> app;

    // REST Endpoints
    CROW_ROUTE(app, "/api/status")([&sim]() {
        auto status_json = nlohmann::json(sim.GetStatus()).dump();
        crow::response res(status_json);
        res.add_header("Content-Type", "application/json");
        return res;
    });

    CROW_ROUTE(app, "/api/config").methods(crow::HTTPMethod::GET)([&sim]() {
        auto config_json = nlohmann::json(sim.GetStatus().config).dump();
        crow::response res(config_json);
        res.add_header("Content-Type", "application/json");
        return res;
    });

    CROW_ROUTE(app, "/api/config").methods(crow::HTTPMethod::POST)([&sim](const crow::request& req) {
        try {
            auto body = nlohmann::json::parse(req.body);
            simulator::Config new_config = body.get<simulator::Config>();
            sim.UpdateConfig(new_config);
            crow::response res(200, "{\"success\": true}");
            res.add_header("Content-Type", "application/json");
            return res;
        } catch (const std::exception& e) {
            return crow::response(400, "{\"error\": \"" + std::string(e.what()) + "\"}");
        }
    });

    CROW_ROUTE(app, "/api/start").methods(crow::HTTPMethod::POST)([&sim]() {
        sim.Start();
        crow::response res(200, "{\"success\": true, \"message\": \"Simulator started\"}");
        res.add_header("Content-Type", "application/json");
        return res;
    });

    CROW_ROUTE(app, "/api/stop").methods(crow::HTTPMethod::POST)([&sim]() {
        sim.Stop();
        crow::response res(200, "{\"success\": true, \"message\": \"Simulator stopped\"}");
        res.add_header("Content-Type", "application/json");
        return res;
    });

    // Get port from environment variable or use default
    const char* port_env = std::getenv("PORT");
    uint16_t port = port_env ? static_cast<uint16_t>(std::stoi(port_env)) : 8080;

    std::cout << "Starting C++ Simulator Server on port " << port << "..." << std::endl;
    app.port(port).multithreaded().run();

    return 0;
}
