#include "simulator.hpp"
#include <iostream>
#include <fstream>
#include <set>
#include <mutex>
#include "types.hpp"
#include <nlohmann/json.hpp>
#include <crow.h>

using json = nlohmann::json;

struct GlobalCORSMiddleware {
    struct context {};

    void before_handle(crow::request& req, crow::response& res, context& /*ctx*/) {
        // Just set the Vary header at the start
        res.set_header("Vary", "Origin");
    }

    void after_handle(crow::request& req, crow::response& res, context& /*ctx*/) {
        std::string origin = req.get_header_value("Origin");
        if (origin.empty()) origin = "*";
        
        // Ensure CORS headers are present on EVERY response
        res.set_header("Access-Control-Allow-Origin", origin);
        res.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE");
        res.set_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With, Origin, Accept");
        res.set_header("Access-Control-Allow-Credentials", "true");
        res.set_header("Access-Control-Max-Age", "3600");
    }
};


int main(int argc, char* argv[]) {
    // Disable stdout buffering for immediate Cloud Run logs
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    try {
        std::cout << "Starting boot sequence..." << std::endl;
        
        // Load config
        std::string config_path = "config.json";
        if (argc > 1) config_path = argv[1];

        std::cout << "Loading config from " << config_path << "..." << std::endl;
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
        if (config.bigquery_dataset_id.empty()) config.bigquery_dataset_id = "paywall_datasets";
        if (config.bigquery_table_id.empty()) config.bigquery_table_id = "bidask_all_staged";

        std::cout << "Initializing Simulator for project " << config.gcp_project_id << "..." << std::endl;
        simulator::Simulator sim(config);

        crow::App<GlobalCORSMiddleware> app; 
        app.loglevel(crow::LogLevel::Debug);

        // Explicitly handle all OPTIONS requests globally as a fallback
        CROW_CATCHALL_ROUTE(app)
        ([&](const crow::request& req, crow::response& res) {
            if (req.method == crow::HTTPMethod::Options) {
                std::string origin = req.get_header_value("Origin");
                if (origin.empty()) origin = "*";
                res.code = 200;
                res.set_header("Access-Control-Allow-Origin", origin);
                res.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE");
                res.set_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With, Origin, Accept");
                res.set_header("Access-Control-Allow-Credentials", "true");
                res.body = "OK";
                res.end();
            } else {
                res.code = 404;
                res.body = "Not Found";
                res.end();
            }
        });

        // WebSocket state
        static std::mutex connections_mutex;
        static std::set<crow::websocket::connection*> connections;

        sim.SetCallbacks(
            [](const simulator::PricingMessage& msg) {
                std::lock_guard<std::mutex> lock(connections_mutex);
                std::string payload = "42[\"message\"," + nlohmann::json(msg).dump() + "]";
                for (auto conn : connections) {
                    try { conn->send_text(payload); } catch (...) {}
                }
            },
            [](const simulator::PriceUpdate& pu) {
                std::lock_guard<std::mutex> lock(connections_mutex);
                std::string payload = "42[\"priceUpdate\"," + nlohmann::json(pu).dump() + "]";
                for (auto conn : connections) {
                    try { conn->send_text(payload); } catch (...) {}
                }
            },
            [](const simulator::BurstProgress& prog) {
                std::lock_guard<std::mutex> lock(connections_mutex);
                std::string payload = "42[\"burstProgress\"," + nlohmann::json(prog).dump() + "]";
                for (auto conn : connections) {
                    try { conn->send_text(payload); } catch (...) {}
                }
            }
        );

        CROW_WEBSOCKET_ROUTE(app, "/socket.io/")
            .onopen([&sim](crow::websocket::connection& conn) {
                std::lock_guard<std::mutex> lock(connections_mutex);
                connections.insert(&conn);
                json handshake = {{"sid", "simulator-cpp-session"},{"upgrades", json::array()},{"pingInterval", 25000},{"pingTimeout", 5000}};
                conn.send_text("0" + handshake.dump());
                conn.send_text("40");
                conn.send_text("42[\"status\"," + nlohmann::json(sim.GetStatus()).dump() + "]");
                conn.send_text("42[\"prices\"," + nlohmann::json(sim.GetPrices()).dump() + "]");
            })
            .onclose([](crow::websocket::connection& conn, const std::string&) {
                std::lock_guard<std::mutex> lock(connections_mutex);
                connections.erase(&conn);
            })
            .onmessage([](crow::websocket::connection& conn, const std::string& data, bool) {
                if (data == "2") conn.send_text("3");
            });

        CROW_ROUTE(app, "/api/status").methods("GET"_method, "OPTIONS"_method)
        ([&sim](const crow::request& req) {
            if (req.method == "OPTIONS"_method) return crow::response(200, "OK");
            return crow::response(nlohmann::json(sim.GetStatus()).dump());
        });

        CROW_ROUTE(app, "/").methods("GET"_method)([]() { return "OK"; });
        CROW_ROUTE(app, "/healthz").methods("GET"_method)([]() { return "OK"; });

        CROW_ROUTE(app, "/api/prices").methods("GET"_method, "OPTIONS"_method)
        ([&sim](const crow::request& req) {
            if (req.method == "OPTIONS"_method) return crow::response(200, "OK");
            return crow::response(nlohmann::json(sim.GetPrices()).dump());
        });

        CROW_ROUTE(app, "/api/config").methods("GET"_method, "POST"_method, "OPTIONS"_method)
        ([&sim](const crow::request& req) {
            if (req.method == "OPTIONS"_method) return crow::response(200, "OK");
            if (req.method == "GET"_method) return crow::response(nlohmann::json(sim.GetStatus().config).dump());
            try {
                auto body = nlohmann::json::parse(req.body);
                sim.UpdateConfig(body.get<simulator::Config>());
                return crow::response(200, "{\"success\": true}");
            } catch (const std::exception& e) {
                return crow::response(400, "{\"error\": \"" + std::string(e.what()) + "\"}");
            }
        });

        CROW_ROUTE(app, "/api/start").methods("POST"_method, "OPTIONS"_method)
        ([&sim](const crow::request& req) {
            if (req.method == "OPTIONS"_method) return crow::response(200, "OK");
            sim.Start();
            return crow::response(200, "{\"success\": true}");
        });

        CROW_ROUTE(app, "/api/stop").methods("POST"_method, "OPTIONS"_method)
        ([&sim](const crow::request& req) {
            if (req.method == "OPTIONS"_method) return crow::response(200, "OK");
            sim.Stop();
            return crow::response(200, "{\"success\": true}");
        });

        const char* port_env = std::getenv("PORT");
        uint16_t port = port_env ? static_cast<uint16_t>(std::stoi(port_env)) : 8080;

        std::cout << "Starting C++ Simulator Server on [::]:" << port << "..." << std::endl;
        app.bindaddr("::").port(port).multithreaded().run();

    } catch (const std::exception& e) {
        std::cerr << "FATAL ERROR during startup: " << e.what() << std::endl;
        return 1;
    } catch (...) {
        std::cerr << "UNKNOWN FATAL ERROR during startup" << std::endl;
        return 1;
    }

    return 0;
}



