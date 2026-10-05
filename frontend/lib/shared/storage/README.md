# storage

后续存储初始化、序列化、查询、事务和迁移，由 Repository 调用，不依赖页面或 Controller。

依赖方向：Presentation → Controller → Repository → Storage。模型和纯算法不得依赖页面。单一模块的实现由对应 feature 管理，共享契约变更需协调模块负责人。

本次仅建立目录约定，没有业务实现、业务模型、算法、数据库依赖或真实数据。
