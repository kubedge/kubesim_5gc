/*
Copyright 2018 Kubedge

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main
import (
  "log"
  "net/http"
  "strings"
  "github.com/kubedge/kubesim_base/grpc/go/kubedge_server"
  "github.com/kubedge/kubesim_base/config"
  "github.com/kubedge/kubesim_base/connected"
)
func sayHello(w http.ResponseWriter, r *http.Request) {
  message := r.URL.Path
  message = strings.TrimPrefix(message, "/")
  message = "kubesim 5gc simulator " + message
  w.Write([]byte(message))
}
func main() {
  log.Printf("%s", "kubesim_5gc is running")


  var conf config.Configdata
  conf.Config()
  log.Printf("5gc server:  product_name=%s, product_type=%s, product_family=%s, product_release=%s, feature_set1=%s, feature_set2=%s",
             conf.Product_name, conf.Product_type, conf.Product_family, conf.Product_release, conf.Feature_set1, conf.Feature_set2)

  var conn connected.Connecteddata
  conn.Readconnectvalues()
  log.Printf("5gc server:  connected=%s", conn.Connected)

  //run server forever
  server.Server(conf)
  http.HandleFunc("/", sayHello)
  if err := http.ListenAndServe(":8080", nil); err != nil {
    panic(err)
  }
}
