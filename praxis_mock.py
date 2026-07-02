from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/api/v1/sandbox/<sandbox_id>/policy', methods=['PUT'])
def update_policy(sandbox_id):
    policy_yaml = request.data.decode('utf-8')
    print(f"[Praxis Mock] Received policy for {sandbox_id}:")
    print(policy_yaml)
    return jsonify({"status": "accepted", "sandbox_id": sandbox_id})

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9090)