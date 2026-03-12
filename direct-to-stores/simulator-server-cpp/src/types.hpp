#pragma once

#include <string>
#include <vector>
#include <nlohmann/json.hpp>

namespace simulator {

using json = nlohmann::json;

struct Config {
    uint64_t periodicity_ms = 1000;
    double price_variation_percentage = 0.5;
    std::string gcp_project_id;
    std::string bigquery_dataset_id;
    std::string bigquery_table_id;
    std::vector<std::string> symbols;
    std::vector<std::string> currencies;
    std::vector<std::string> venues;
    uint64_t burst_size = 1000;
    std::string pubsub_topic_name;
    uint64_t pubsub_batch_messages = 1000;
    uint64_t pubsub_batch_delay_ms = 10;

    // Manual to_json to match UI camelCase requirements
    friend void to_json(nlohmann::json& j, const Config& c) {
        j = nlohmann::json{
            {"periodicityMs", c.periodicity_ms},
            {"priceVariationPercentage", c.price_variation_percentage},
            {"gcpProjectId", c.gcp_project_id},
            {"bigqueryDatasetId", c.bigquery_dataset_id},
            {"bigqueryTableId", c.bigquery_table_id},
            {"symbols", c.symbols},
            {"currencies", c.currencies},
            {"venues", c.venues},
            {"burstSize", c.burst_size},
            {"pubsubTopicName", c.pubsub_topic_name},
            {"pubsubBatchMessages", c.pubsub_batch_messages},
            {"pubsubBatchDelayMs", c.pubsub_batch_delay_ms}
        };
    }

    friend void from_json(const nlohmann::json& j, Config& c) {
        c.periodicity_ms = j.value("periodicityMs", 1000UL);
        c.price_variation_percentage = j.value("priceVariationPercentage", 0.5);
        c.gcp_project_id = j.value("gcpProjectId", "");
        c.bigquery_dataset_id = j.value("bigqueryDatasetId", "simulator_data");
        c.bigquery_table_id = j.value("bigqueryTableId", "order_ticks_delay");
        if (j.contains("symbols")) c.symbols = j.at("symbols").get<std::vector<std::string>>();
        if (j.contains("currencies")) c.currencies = j.at("currencies").get<std::vector<std::string>>();
        if (j.contains("venues")) c.venues = j.at("venues").get<std::vector<std::string>>();
        c.burst_size = j.value("burstSize", 1000UL);
        c.pubsub_topic_name = j.value("pubsubTopicName", "");
        c.pubsub_batch_messages = j.value("pubsubBatchMessages", 1000UL);
        c.pubsub_batch_delay_ms = j.value("pubsubBatchDelayMs", 10UL);
    }
};

struct PricingMessage {
    std::string symbol;
    uint64_t sequence_number;
    double price;
    std::string currency;
    std::string venue;
    std::string timestamp; // ISO 8601
    std::string bid_ask;   // "bid" or "ask"
    uint64_t quantity;
    std::string publish_time;

    friend void to_json(nlohmann::json& j, const PricingMessage& m) {
        j = nlohmann::json{
            {"symbol", m.symbol},
            {"sequenceNumber", m.sequence_number},
            {"price", m.price},
            {"currency", m.currency},
            {"venue", m.venue},
            {"timestamp", m.timestamp},
            {"bidAsk", m.bid_ask},
            {"quantity", m.quantity},
            {"publishTime", m.publish_time}
        };
    }
};

struct PriceUpdate {
    std::string symbol;
    std::string currency;
    double price;
    std::string bid_ask;

    friend void to_json(nlohmann::json& j, const PriceUpdate& u) {
        j = nlohmann::json{
            {"symbol", u.symbol},
            {"currency", u.currency},
            {"price", u.price},
            {"bidAsk", u.bid_ask}
        };
    }
};

struct BurstProgress {
    uint8_t percent_complete;
    uint64_t message_count;
    std::string phase; // "generating" or "publishing"

    friend void to_json(nlohmann::json& j, const BurstProgress& p) {
        j = nlohmann::json{
            {"percentComplete", p.percent_complete},
            {"messageCount", p.message_count},
            {"phase", p.phase}
        };
    }
};

struct Status {
    bool is_running;
    Config config;

    friend void to_json(nlohmann::json& j, const Status& s) {
        j = nlohmann::json{
            {"isRunning", s.is_running},
            {"config", s.config}
        };
    }
};

} // namespace simulator
