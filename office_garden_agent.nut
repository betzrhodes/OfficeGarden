/******************** Library Code *************************/
class SparkFunStream {
    _baseUrl = null;

    _publicKey = null;
    _privateKey = null;

    constructor(baseUrl, publicKey, privateKey) {
        _baseUrl = baseUrl;
        _privateKey = privateKey;
        _publicKey = publicKey;
    }

    function push(data, cb = null) {
        assert(typeof(data == "table"));

        // add private key to table
        data["private_key"] <- _privateKey;
        local url = format("https://%s/input/%s?%s", _baseUrl, _publicKey, http.urlencode(data));

        // make the request
        local request = http.get(url);
        if (cb == null) {
            return request.sendsync();
        }

        request.sendasync(cb);
    }

    function get(cb = null) {
        local url = format("https://%s/output/%s.json", _baseUrl, _publicKey);

        local request = http.get(url);
        if(cb == null) {
            return request.sendsync();
        }
        return request.sendasync(cb);
    }

    function clear(cb = null) {
        local url = format("https://%s/input/%s/clear", _baseUrl, _publicKey);
        local headers = { "phant-private-key": _privateKey };

        local request = http.httpdelete(url, headers);
        if (cb == null) {
            return request.sendsync();
        }
        return request.sendasync(cb);
    }
}

/******************** Application Code ********************/
// Create a Sparkfun Data Stream
// delete key k3RqWqBqLKfpobrBgqwO

const SPARKFUN_BASE = "data.sparkfun.com";
const SPARKFUN_PUBLIC_KEY = "";
const SPARKFUN_PRIVATE_KEY = "";

stream <- SparkFunStream(SPARKFUN_BASE, SPARKFUN_PUBLIC_KEY, SPARKFUN_PRIVATE_KEY);

// //Syncronous Push:
// local resp = stream.push(data);
// server.log(format("PUSH: %i - %s", resp.statuscode, resp.body));

//Asyncronous Push:
device.on("data", function(data){
        stream.push(data, function(resp) {
        server.log(format("PUSH: %i - %s", resp.statuscode, resp.body));
    })
});
