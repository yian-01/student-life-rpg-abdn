# repositories

后续共享数据访问契约和实现，隔离 Controller 与 Storage；页面不直接访问存储。

依赖方向：Presentation → Controller → Repository → Storage。模型和纯算法不得依赖页面。单一模块的实现由对应 feature 管理，共享契约变更需协调模块负责人。

本次仅建立目录约定，没有业务实现、业务模型、算法、数据库依赖或真实数据。
