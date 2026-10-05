# controllers

后续共享应用状态、校验和工作流协调。Controller 使用 Flutter SDK 的 ChangeNotifier，不依赖页面。

依赖方向：Presentation → Controller → Repository → Storage。模型和纯算法不得依赖页面。单一模块的实现由对应 feature 管理，共享契约变更需协调模块负责人。

本次仅建立目录约定，没有业务实现、业务模型、算法、数据库依赖或真实数据。
